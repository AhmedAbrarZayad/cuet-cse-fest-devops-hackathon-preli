# Build Stage
FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .

# Runtime Stage
FROM node:18-alpine
WORKDIR /app
USER node
COPY --from=builder --chown=node:node /app .
EXPOSE 5921
CMD ["npm", "start"]