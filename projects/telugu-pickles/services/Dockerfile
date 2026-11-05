# One Dockerfile for all six Node.js services.
#   docker build --build-arg SERVICE=catalog-service -t telugu-pickles/catalog-service .
#
# Image layout:  /app/node_modules  /app/common  /app/<service>
FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund && npm cache clean --force

FROM node:22-alpine
# Latest Alpine security fixes, and drop package managers the services never use at
# runtime (npm/yarn/corepack carry most of the image's CVEs and help attackers).
RUN apk upgrade --no-cache \
 && rm -rf /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/corepack \
           /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack \
           /opt/yarn-* /usr/local/bin/yarn /usr/local/bin/yarnpkg
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
