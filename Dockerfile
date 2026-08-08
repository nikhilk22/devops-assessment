# =============================================================================
# VexarDrive Fleet Ping Service — Production Dockerfile
# Multi-stage build: separate install from runtime for minimal attack surface
# =============================================================================

# ---- Stage 1: Build ----
FROM node:20-alpine AS builder

WORKDIR /app

# Copy dependency manifests first
COPY package.json package-lock.json ./

# Install production dependencies only (cache-friendly layer)
RUN npm ci --only=production && \
    # Remove unnecessary files from node_modules to reduce size
    rm -rf /app/node_modules/.cache

# ---- Stage 2: Runtime ----
FROM node:20-alpine AS runtime

# Add non-root user
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

# Copy only production dependencies from builder
COPY --from=builder /app/node_modules ./node_modules

# Copy application code
COPY server.js ./

# Security: drop root privileges
USER appuser

# Security: make app directory read-only (writes go to /tmp if needed)
# (Read-only root filesystem is enforced at the container runtime level)

# Container health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

# Application port
EXPOSE 3000

# Use tini for proper signal handling
RUN apk add --no-cache tini
ENTRYPOINT ["/sbin/tini", "--"]

CMD ["node", "server.js"]
