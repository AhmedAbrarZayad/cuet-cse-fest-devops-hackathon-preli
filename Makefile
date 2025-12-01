# Docker Services:
#   up - Start services (use: make up [service...] or make up MODE=prod, ARGS="--build" for options)
#   down - Stop services (use: make down [service...] or make down MODE=prod, ARGS="--volumes" for options)
#   build - Build containers (use: make build [service...] or make build MODE=prod)
#   logs - View logs (use: make logs [service] or make logs SERVICE=backend, MODE=prod for production)
#   restart - Restart services (use: make restart [service...] or make restart MODE=prod)
#   shell - Open shell in container (use: make shell [service] or make shell SERVICE=gateway, MODE=prod, default: backend)
#   ps - Show running containers (use MODE=prod for production)
#
# Convenience Aliases (Development):
#   dev-up - Alias: Start development environment
#   dev-down - Alias: Stop development environment
#   dev-build - Alias: Build development containers
#   dev-logs - Alias: View development logs
#   dev-restart - Alias: Restart development services
#   dev-shell - Alias: Open shell in backend container
#   dev-ps - Alias: Show running development containers
#   backend-shell - Alias: Open shell in backend container
#   gateway-shell - Alias: Open shell in gateway container
#   mongo-shell - Open MongoDB shell
#
# Convenience Aliases (Production):
#   prod-up - Alias: Start production environment
#   prod-down - Alias: Stop production environment
#   prod-build - Alias: Build production containers
#   prod-logs - Alias: View production logs
#   prod-restart - Alias: Restart production services
#
# Backend:
#   backend-build - Build backend TypeScript
#   backend-install - Install backend dependencies
#   backend-type-check - Type check backend code
#   backend-dev - Run backend in development mode (local, not Docker)
#
# Database:
#   db-reset - Reset MongoDB database (WARNING: deletes all data)
#   db-backup - Backup MongoDB database
#
# Cleanup:
#   clean - Remove containers and networks (both dev and prod)
#   clean-all - Remove containers, networks, volumes, and images
#   clean-volumes - Remove all volumes
#
# Utilities:
#   status - Alias for ps
#   health - Check service health
#
# Help:
#   help - Display this help message

.PHONY: help up down build logs restart shell ps dev-up dev-down dev-build dev-logs dev-restart dev-shell dev-ps prod-up prod-down prod-build prod-logs prod-restart backend-shell gateway-shell mongo-shell backend-build backend-install backend-type-check backend-dev db-reset db-backup clean clean-all clean-volumes status health

# Default variables
MODE ?= dev
SERVICE ?= backend
COMPOSE_FILE_DEV = docker/compose.development.yaml
COMPOSE_FILE_PROD = docker/compose.production.yaml

# Determine which compose file to use
ifeq ($(MODE),prod)
	COMPOSE_FILE = $(COMPOSE_FILE_PROD)
else
	COMPOSE_FILE = $(COMPOSE_FILE_DEV)
endif

# Help command
help:
	@echo "Available commands:"
	@echo "  make dev-up          - Start development environment"
	@echo "  make dev-down        - Stop development environment"
	@echo "  make dev-build       - Build development containers"
	@echo "  make dev-logs        - View development logs"
	@echo "  make prod-up         - Start production environment"
	@echo "  make prod-down       - Stop production environment"
	@echo "  make prod-build      - Build production containers"
	@echo "  make health          - Check service health"
	@echo "  make clean           - Remove containers and networks"
	@echo "  make clean-all       - Remove everything including volumes"

# Docker Services
up:
	docker compose -f $(COMPOSE_FILE) up -d $(ARGS)

down:
	docker compose -f $(COMPOSE_FILE) down $(ARGS)

build:
	docker compose -f $(COMPOSE_FILE) build $(ARGS)

logs:
	docker compose -f $(COMPOSE_FILE) logs -f $(SERVICE)

restart:
	docker compose -f $(COMPOSE_FILE) restart $(ARGS)

shell:
	docker compose -f $(COMPOSE_FILE) exec $(SERVICE) sh

ps:
	docker compose -f $(COMPOSE_FILE) ps

# Development aliases
dev-up:
	docker compose -f $(COMPOSE_FILE_DEV) up -d

dev-down:
	docker compose -f $(COMPOSE_FILE_DEV) down

dev-build:
	docker compose -f $(COMPOSE_FILE_DEV) build

dev-logs:
	docker compose -f $(COMPOSE_FILE_DEV) logs -f

dev-restart:
	docker compose -f $(COMPOSE_FILE_DEV) restart

dev-shell:
	docker compose -f $(COMPOSE_FILE_DEV) exec backend sh

dev-ps:
	docker compose -f $(COMPOSE_FILE_DEV) ps

backend-shell:
	docker compose -f $(COMPOSE_FILE_DEV) exec backend sh

gateway-shell:
	docker compose -f $(COMPOSE_FILE_DEV) exec gateway sh

mongo-shell:
	docker compose -f $(COMPOSE_FILE_DEV) exec mongo mongosh -u $(MONGO_INITDB_ROOT_USERNAME) -p $(MONGO_INITDB_ROOT_PASSWORD)

# Production aliases
prod-up:
	docker compose -f $(COMPOSE_FILE_PROD) up -d

prod-down:
	docker compose -f $(COMPOSE_FILE_PROD) down

prod-build:
	docker compose -f $(COMPOSE_FILE_PROD) build

prod-logs:
	docker compose -f $(COMPOSE_FILE_PROD) logs -f

prod-restart:
	docker compose -f $(COMPOSE_FILE_PROD) restart

# Backend commands
backend-build:
	cd backend && npm run build

backend-install:
	cd backend && npm install

backend-type-check:
	cd backend && npm run type-check

backend-dev:
	cd backend && npm run dev

# Database commands
db-reset:
	docker compose -f $(COMPOSE_FILE) down -v
	docker compose -f $(COMPOSE_FILE) up -d

db-backup:
	docker compose -f $(COMPOSE_FILE) exec mongo mongodump --out=/data/backup --username=$(MONGO_INITDB_ROOT_USERNAME) --password=$(MONGO_INITDB_ROOT_PASSWORD)

# Cleanup commands
clean:
	docker compose -f $(COMPOSE_FILE_DEV) down
	docker compose -f $(COMPOSE_FILE_PROD) down

clean-all:
	docker compose -f $(COMPOSE_FILE_DEV) down -v --rmi all
	docker compose -f $(COMPOSE_FILE_PROD) down -v --rmi all

clean-volumes:
	docker compose -f $(COMPOSE_FILE_DEV) down -v
	docker compose -f $(COMPOSE_FILE_PROD) down -v

# Utilities
status: ps

health:
	@echo "Checking gateway health..."
	@curl -f http://localhost:5921/health || echo "Gateway is down"
	@echo "\nChecking backend health via gateway..."
	@curl -f http://localhost:5921/api/health || echo "Backend is down"
