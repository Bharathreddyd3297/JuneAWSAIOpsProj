# One Dockerfile for all six Node.js services.
#   docker build --build-arg SERVICE=catalog-service -t telugu-pickles/catalog-service .
#
# Image layout:  /app/node_modules  /app/common  /app/<service>
FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund && npm cache clean --force

FROM node:22-alpine
ARG SERVICE
ENV NODE_ENV=production \
    SERVICE=${SERVICE}
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY package.json ./
COPY common ./common
COPY ${SERVICE} ./${SERVICE}

# run as the unprivileged "node" user that ships with the image
USER node

# Docker-level health check (Kubernetes uses its own probes on /health/*)
HEALTHCHECK --interval=15s --timeout=3s --start-period=30s --retries=3 \
  CMD wget -qO- "http://127.0.0.1:${PORT:-8080}/health/live" >/dev/null || exit 1

CMD ["sh", "-c", "exec node ${SERVICE}/src/index.js"]
