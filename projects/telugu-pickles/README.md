# Telugu Pickles — తెలుగు పచ్చళ్ళు

E-commerce store for authentic Indian veg & non-veg pickles (20 veg + 16 non-veg), built as
6 Node.js microservices + a React frontend for the DevOps + AIOps series.

**Full system design:** [`docs/telugu-pickles-system-design.html`](../../docs/telugu-pickles-system-design.html) (open in a browser)

```
frontend (nginx + React)  ->  gateway :8080  ->  auth-service    :4001  auth_db
                                              ->  catalog-service :4002  catalog_db
                                              ->  cart-service    :4003  cart_db
                                              ->  order-service   :4004  orders_db  -> payment-service :4005 (internal)
                                                                                        payments_db
```

## Run locally

**New to Docker? Follow the step-by-step student guide: [LOCAL-SETUP.md](LOCAL-SETUP.md)**. It covers installing,
running, testing and troubleshooting on Windows, macOS and Linux.

```bash
docker compose up -d --build
./scripts/smoke-test.sh          # 25 end-to-end checks
```

| URL | |
|---|---|
| http://localhost:3000 | Store — demo login `demo@telugupickles.in` / `Pickle@123` |
| http://localhost:8080/api/health | Gateway aggregated health |
| http://localhost:9090 | Prometheus |
| http://localhost:3001 | Grafana (admin / admin) |

Dev mode without Docker for the UI: start the stack, then `cd frontend && npm install && npm run dev` (Vite proxies `/api` to :8080).

## Layout

```
services/            one package + one Dockerfile for all 6 services
  common/            logger, metrics, db bootstrap, auth, http client, pricing, service framework
  <service>/src/     each service's entry point
  test/              node:test unit tests  (npm test)
frontend/            React + Vite, nginx template that proxies /api
observability/       Prometheus config + Grafana provisioning & dashboard
scripts/             smoke-test.sh, push-to-ecr.sh, build-dashboard.js
```

**Deploy to AWS EKS** (GitHub Actions + Terraform + Argo CD): [`docs/CICD-EKS-GUIDE.md`](../../docs/CICD-EKS-GUIDE.md).

Kubernetes manifests live in [`/gitops`](../../gitops), Terraform in [`/projects/Infrastructure`](../Infrastructure),
CI in [`/.github/workflows/ci.yml`](../../.github/workflows/ci.yml).

## Fault injection (AIOps demo)

| Env var | Service | Effect |
|---|---|---|
| `PAYMENT_DECLINE_RATE=0.5` | payment-service | 50% of UPI/card payments declined |
| `PAYMENT_LATENCY_MS=4000` | payment-service | slow payments |
| `CHAOS_ERROR_RATE=0.3` | any | 30% of requests return 503 |
| `CHAOS_LATENCY_MS=1500` | any | added latency |

Locally: `PAYMENT_DECLINE_RATE=0.5 docker compose up -d payment-service`.
On EKS: edit `gitops/k8s/platform/config.yml`, commit, Argo CD syncs (restart pods to pick up env).
