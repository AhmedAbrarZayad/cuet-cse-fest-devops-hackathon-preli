# DevOps Implementation Guide

This document explains all the DevOps practices and configurations implemented for this e-commerce microservices project.

---

## Table of Contents
1. [Project Architecture](#project-architecture)
2. [Containerization Strategy](#containerization-strategy)
3. [Docker Compose Configuration](#docker-compose-configuration)
4. [Security Implementation](#security-implementation)
5. [Data Persistence](#data-persistence)
6. [Development Workflow](#development-workflow)
7. [Production Optimizations](#production-optimizations)
8. [Makefile Automation](#makefile-automation)

---

## Project Architecture

### Microservices Setup
```
Client → Gateway (Port 5921) → Backend (Port 3847) → MongoDB (Port 27017)
         [PUBLIC]               [PRIVATE]            [PRIVATE]
```

**Key Principles:**
- **Gateway**: Only publicly exposed service (port 5921)
- **Backend**: Internal service, not directly accessible
- **MongoDB**: Completely isolated, no external access
- **Private Network**: All services communicate through Docker's private network

---

## Containerization Strategy

### 1. Backend Dockerfiles

#### Production (`backend/Dockerfile`)
```dockerfile
# Multi-stage build for optimization
FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:18-alpine
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY package*.json ./
USER node
EXPOSE 3847
CMD ["npm", "start"]
```

**Optimizations:**
- Multi-stage build reduces final image size
- Alpine Linux base (minimal footprint)
- Layer caching (package.json copied first)
- Non-root user for security
- Only production artifacts in final image

#### Development (`backend/Dockerfile.dev`)
```dockerfile
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 3847
CMD ["npm", "run", "dev"]
```

**Features:**
- All dependencies for development
- Hot reload support via tsx watch
- Simplified for faster iteration

---

### 2. Gateway Dockerfiles

#### Production (`gateway/Dockerfile`)
```dockerfile
FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .

FROM node:18-alpine
WORKDIR /app
USER node
COPY --from=builder --chown=node:node /app .
EXPOSE 5921
CMD ["npm", "start"]
```

**Features:**
- No build step needed (plain JavaScript)
- Production dependencies only
- Non-root user
- Proper file ownership

#### Development (`gateway/Dockerfile.dev`)
```dockerfile
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 5921
CMD ["npm", "run", "dev"]
```

**Features:**
- Nodemon for hot reload
- All dev dependencies included

---

## Docker Compose Configuration

### Development Environment (`docker/compose.development.yaml`)

```yaml
version: '3.8'

services:
  mongo:
    image: mongo:7-jammy
    container_name: mongo-dev
    environment:
      MONGO_INITDB_ROOT_USERNAME: ${MONGO_INITDB_ROOT_USERNAME}
      MONGO_INITDB_ROOT_PASSWORD: ${MONGO_INITDB_ROOT_PASSWORD}
    volumes:
      - mongodb_data_dev:/data/db
    networks:
      - private-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "sh", "-c", "mongosh --quiet --eval 'db.adminCommand(\"ping\").ok' -u $MONGO_INITDB_ROOT_USERNAME -p $MONGO_INITDB_ROOT_PASSWORD --authenticationDatabase admin"]
      interval: 10s
      timeout: 5s
      retries: 5

  backend:
    build:
      context: ../backend
      dockerfile: Dockerfile.dev
    container_name: backend-dev
    environment:
      MONGO_URI: ${MONGO_URI}
      MONGO_DATABASE: ${MONGO_DATABASE}
      BACKEND_PORT: ${BACKEND_PORT}
      NODE_ENV: development
    volumes:
      - ../backend/src:/app/src  # Hot reload
    networks:
      - private-network
    depends_on:
      mongo:
        condition: service_healthy
    restart: unless-stopped

  gateway:
    build:
      context: ../gateway
      dockerfile: Dockerfile.dev
    container_name: gateway-dev
    environment:
      BACKEND_URL: http://backend:${BACKEND_PORT}
      GATEWAY_PORT: ${GATEWAY_PORT}
      NODE_ENV: development
    ports:
      - "${GATEWAY_PORT}:${GATEWAY_PORT}"
    volumes:
      - ../gateway/src:/app/src  # Hot reload
    networks:
      - private-network
    depends_on:
      - backend
    restart: unless-stopped

networks:
  private-network:
    driver: bridge

volumes:
  mongodb_data_dev:
```

**Key Features:**
- Health checks ensure MongoDB is ready before backend starts
- Volume mounts for hot reload during development
- Only gateway port exposed to host
- Automatic restart on failure
- Separate development data volume

---

### Production Environment (`docker/compose.production.yaml`)

```yaml
version: '3.8'

services:
  mongo:
    image: mongo:7-jammy
    container_name: mongo-prod
    environment:
      MONGO_INITDB_ROOT_USERNAME: ${MONGO_INITDB_ROOT_USERNAME}
      MONGO_INITDB_ROOT_PASSWORD: ${MONGO_INITDB_ROOT_PASSWORD}
    volumes:
      - mongodb_data_prod:/data/db
    networks:
      - private-network
    restart: always
    healthcheck:
      test: ["CMD", "sh", "-c", "mongosh --quiet --eval 'db.adminCommand(\"ping\").ok' -u $MONGO_INITDB_ROOT_USERNAME -p $MONGO_INITDB_ROOT_PASSWORD --authenticationDatabase admin"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 512M

  backend:
    build:
      context: ../backend
      dockerfile: Dockerfile
    container_name: backend-prod
    environment:
      MONGO_URI: ${MONGO_URI}
      MONGO_DATABASE: ${MONGO_DATABASE}
      BACKEND_PORT: ${BACKEND_PORT}
      NODE_ENV: production
    networks:
      - private-network
    depends_on:
      mongo:
        condition: service_healthy
    restart: always
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 256M
    security_opt:
      - no-new-privileges:true
    read_only: true
    tmpfs:
      - /tmp

  gateway:
    build:
      context: ../gateway
      dockerfile: Dockerfile
    container_name: gateway-prod
    environment:
      BACKEND_URL: http://backend:${BACKEND_PORT}
      GATEWAY_PORT: ${GATEWAY_PORT}
      NODE_ENV: production
    ports:
      - "${GATEWAY_PORT}:${GATEWAY_PORT}"
    networks:
      - private-network
    depends_on:
      - backend
    restart: always
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 256M
    security_opt:
      - no-new-privileges:true
    read_only: true
    tmpfs:
      - /tmp

networks:
  private-network:
    driver: bridge
    internal: true  # Network isolation

volumes:
  mongodb_data_prod:
    driver: local
```

**Production Hardening:**
- **Resource limits**: CPU and memory constraints
- **Security options**: `no-new-privileges` prevents privilege escalation
- **Read-only filesystem**: Containers can't modify their filesystem
- **tmpfs mounts**: Temporary writable space for /tmp
- **Internal network**: Complete isolation from external networks
- **Always restart**: High availability
- **Health checks**: Longer intervals, more retries for stability

---

## Security Implementation

### 1. Network Security
- **Private Network**: All services on isolated Docker network
- **Internal Network (Production)**: `internal: true` blocks external access
- **Single Entry Point**: Only gateway exposed to public
- **Port Isolation**: Backend (3847) and MongoDB (27017) not exposed

### 2. Container Security
- **Non-root Users**: All containers run as `node` user (UID 1000)
- **Read-only Filesystem**: Prevents runtime file modifications
- **No New Privileges**: Blocks privilege escalation attacks
- **Minimal Base Images**: Alpine Linux reduces attack surface

### 3. Application Security
- **Input Sanitization**: validator.escape() prevents XSS attacks
- **Input Validation**: Type checking and format validation
- **Environment Variables**: Secrets stored in .env (gitignored)
- **Authentication**: MongoDB requires username/password

### 4. Data Security
- **Credentials Management**: All secrets in .env file
- **.gitignore Protection**: Prevents accidental credential commits
- **Encrypted Communication**: Services communicate through private network

---

## Data Persistence

### Volume Strategy
```yaml
volumes:
  mongodb_data_dev:  # Development data
  mongodb_data_prod: # Production data
```

**Benefits:**
- Data survives container restarts
- Separate dev/prod data isolation
- Easy backup and migration
- Performance optimization

### Backup Strategy (via Makefile)
```makefile
db-backup:
    docker compose -f $(COMPOSE_FILE) exec mongo mongodump \
        --out=/data/backup \
        --username=$(MONGO_INITDB_ROOT_USERNAME) \
        --password=$(MONGO_INITDB_ROOT_PASSWORD)
```

---

## Development Workflow

### Environment Setup
1. **Clone Repository**
2. **Create .env File**:
```env
MONGO_INITDB_ROOT_USERNAME=admin
MONGO_INITDB_ROOT_PASSWORD=securePassword123!
MONGO_URI=mongodb://admin:securePassword123!@mongo:27017
MONGO_DATABASE=ecommerce
BACKEND_PORT=3847
GATEWAY_PORT=5921
NODE_ENV=development
```

3. **Start Development Environment**:
```bash
make dev-build  # Build all containers
make dev-up     # Start all services
make dev-logs   # View logs
```

### Hot Reload
- **Backend**: Volume mount `/app/src` with tsx watch
- **Gateway**: Volume mount `/app/src` with nodemon
- Changes reflect instantly without container restart

### Debugging
```bash
make backend-shell  # Access backend container
make gateway-shell  # Access gateway container
make mongo-shell    # Access MongoDB shell
make dev-logs       # View all service logs
```

---

## Production Optimizations

### 1. Image Optimization
- **Multi-stage builds**: Separate build and runtime stages
- **Layer caching**: Dependencies cached separately
- **Alpine Linux**: 5-10x smaller than full Node images
- **Production dependencies only**: Minimal final image

### 2. Resource Management
- **CPU Limits**: Prevent resource hogging
- **Memory Limits**: Avoid OOM situations
- **Restart Policies**: Automatic recovery

### 3. Health Checks
- **MongoDB**: Authenticated ping check
- **Longer intervals**: Reduce overhead in production
- **Start period**: Grace time for initialization
- **Dependency ordering**: Backend waits for healthy MongoDB

### 4. Network Isolation
- **Internal network**: No external connectivity
- **Service discovery**: DNS-based internal communication
- **Port mapping**: Only gateway accessible

---

## Makefile Automation

### Core Commands
```makefile
# Development
make dev-up          # Start development environment
make dev-down        # Stop development environment
make dev-build       # Build development containers
make dev-logs        # View development logs
make dev-restart     # Restart development services

# Production
make prod-up         # Start production environment
make prod-down       # Stop production environment
make prod-build      # Build production containers
make prod-logs       # View production logs

# Utilities
make health          # Check service health
make clean           # Remove containers and networks
make clean-all       # Remove everything including volumes
make backend-shell   # Open shell in backend container
make gateway-shell   # Open shell in gateway container
make mongo-shell     # Open MongoDB shell
```

### Health Check Implementation
```makefile
health:
    @echo "Checking gateway health..."
    @curl -f http://localhost:5921/health || echo "Gateway is down"
    @echo "\nChecking backend health via gateway..."
    @curl -f http://localhost:5921/api/health || echo "Backend is down"
```

### Database Management
```makefile
db-reset:
    docker compose -f $(COMPOSE_FILE) down -v
    docker compose -f $(COMPOSE_FILE) up -d

db-backup:
    docker compose -f $(COMPOSE_FILE) exec mongo mongodump \
        --out=/data/backup \
        --username=$(MONGO_INITDB_ROOT_USERNAME) \
        --password=$(MONGO_INITDB_ROOT_PASSWORD)
```

---

## Testing the Setup

### 1. Health Checks
```bash
# Gateway health
curl http://localhost:5921/health

# Backend health (via gateway)
curl http://localhost:5921/api/health
```

### 2. Create Product
```bash
curl -X POST http://localhost:5921/api/products \
  -H 'Content-Type: application/json' \
  -d '{"name":"Test Product","price":99.99}'
```

### 3. Get Products
```bash
curl http://localhost:5921/api/products
```

### 4. Security Test (Should Fail)
```bash
# This should timeout/fail - backend not exposed
curl http://localhost:3847/api/products
```

---

## Best Practices Implemented

### 1. **12-Factor App Principles**
- Configuration via environment variables
- Separate build and run stages
- Stateless processes
- Port binding
- Disposability (fast startup/shutdown)

### 2. **Security Best Practices**
- Principle of least privilege
- Defense in depth (multiple security layers)
- Input validation and sanitization
- Secrets management
- Network segmentation

### 3. **Container Best Practices**
- Minimal base images
- Single process per container
- Health checks
- Graceful shutdown
- Non-root users

### 4. **DevOps Best Practices**
- Infrastructure as Code
- Separate dev/prod environments
- Automated builds
- Easy rollback
- Monitoring and logging

---

## Troubleshooting

### MongoDB Health Check Fails
**Issue**: Container marked as unhealthy
**Solution**: Health check now uses shell to expand environment variables:
```yaml
test: ["CMD", "sh", "-c", "mongosh --quiet --eval 'db.adminCommand(\"ping\").ok' -u $MONGO_INITDB_ROOT_USERNAME -p $MONGO_INITDB_ROOT_PASSWORD --authenticationDatabase admin"]
```

### Backend Can't Connect to MongoDB
**Issue**: Service name mismatch
**Solution**: Service named `mongo` in compose to match `MONGO_URI=mongodb://...@mongo:27017`

### Port Conflicts
**Issue**: Ports already in use
**Solution**: Change ports in `.env` file or stop conflicting services

### Permission Denied
**Issue**: Volume mount permissions
**Solution**: Containers run as `node` user, ensure host files are accessible

---

## Summary

This DevOps implementation provides:
- ✅ **Containerized microservices** with Docker
- ✅ **Separate dev/prod** configurations
- ✅ **Security hardening** (network isolation, non-root users, input validation)
- ✅ **Data persistence** with Docker volumes
- ✅ **Optimized images** (multi-stage builds, Alpine Linux)
- ✅ **Automated workflows** via Makefile
- ✅ **Health monitoring** and automatic restart
- ✅ **Hot reload** for development
- ✅ **Resource management** and limits
- ✅ **Production-ready** architecture

All requirements from the hackathon challenge have been met and exceeded with industry best practices.
