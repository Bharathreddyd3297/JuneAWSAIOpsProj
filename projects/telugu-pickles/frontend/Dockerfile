# Stage 1: build the static React bundle
FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY . .
RUN npm run build

# Stage 2: serve with nginx; /api is reverse-proxied to the gateway.
# GATEWAY_URL is substituted into the nginx template at container start,
# so the SAME image works in docker-compose and Kubernetes.
FROM nginx:1.30-alpine
# pull the latest Alpine security fixes (the CI Trivy gate fails on fixable CRITICAL CVEs)
RUN apk upgrade --no-cache
ENV GATEWAY_URL=http://gateway:8080
COPY nginx/default.conf.template /etc/nginx/templates/default.conf.template
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
HEALTHCHECK --interval=15s --timeout=3s CMD wget -qO- http://127.0.0.1/healthz >/dev/null || exit 1
