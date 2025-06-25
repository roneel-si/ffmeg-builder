# Multi-stage build for FFmpeg Builder
FROM node:18-alpine AS builder

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production && npm cache clean --force

# Production stage
FROM node:18-alpine

# Install FFmpeg and other dependencies
RUN apk add --no-cache \
    ffmpeg \
    curl \
    bash \
    su-exec \
    tini

# Create app user
RUN addgroup -g 1001 -S ffmpeg-builder && \
    adduser -S ffmpeg-builder -u 1001 -G ffmpeg-builder

# Set working directory
WORKDIR /app

# Copy node_modules from builder stage
COPY --from=builder /app/node_modules ./node_modules

# Copy application files
COPY --chown=ffmpeg-builder:ffmpeg-builder . .

# Create necessary directories
RUN mkdir -p /var/ffmpeg-output /var/log/ffmpeg-builder && \
    chown -R ffmpeg-builder:ffmpeg-builder /var/ffmpeg-output /var/log/ffmpeg-builder

# Set environment variables
ENV NODE_ENV=production \
    PORT=3000 \
    OUTPUT_PATH=/var/ffmpeg-output \
    LOG_FILE_PATH=/var/log/ffmpeg-builder

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:3000/api/health || exit 1

# Use tini as init system
ENTRYPOINT ["/sbin/tini", "--"]

# Switch to non-root user and start application
USER ffmpeg-builder
CMD ["node", "server.js"] 