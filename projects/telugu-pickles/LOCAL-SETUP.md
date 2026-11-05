# Run Telugu Pickles on Your Laptop

This guide takes you from a fresh laptop to a working pickle store at **http://localhost:3000**.
You do **not** need an AWS account, Node.js or PostgreSQL. Docker runs everything for you.

**Time:** about 20 minutes the first time (most of it is downloading). Later starts take under a minute.

---

## What you are about to run

```
 Your browser
     │  http://localhost:3000
     ▼
 frontend  (nginx + React)            ← the website
     │  /api/...
     ▼
 gateway   :8080                       ← one front door for every API call
     ├── auth-service     login, accounts           ─┐
     ├── catalog-service  36 pickles, stock          │
     ├── cart-service     shopping cart              ├── postgres (one database per service)
     └── order-service    checkout ──► payment-service┘

 prometheus :9090  collects metrics    grafana :3001  shows dashboards
```

That is 10 containers in total. Together they use only about **400 MB of RAM** once running.

---

## Step 0 — Check your laptop

| Need | Minimum | Notes |
|---|---|---|
| RAM | 8 GB | 4 GB works with the "lite" start in Step 3 |
| Free disk | 5 GB | Docker images take about 2.5 GB |
| OS | Windows 10/11, macOS 12+, or Ubuntu 22.04+ | Intel and Apple Silicon (M1–M4) Macs both work |
| Internet | Needed for the first build | After that, everything runs offline |

Free ports needed: **3000, 8080, 9090, 3001**. If another app uses one of them, see [Troubleshooting](#troubleshooting).

---

## Step 1 — Install the tools (one time)

### Windows
1. **Git for Windows**: https://git-scm.com/download/win. Accept the defaults. This also gives you **Git Bash**, which you will use for the commands below.
2. **Docker Desktop**: https://www.docker.com/products/docker-desktop/
   - When the installer asks, keep **"Use WSL 2"** ticked.
   - Restart the laptop when told to.
   - If Docker says *"WSL 2 installation is incomplete"*, open **PowerShell as Administrator**, run `wsl --install`, then restart.
3. Open Docker Desktop and wait until the bottom-left corner says **Engine running**.

### macOS
1. **Docker Desktop**: https://www.docker.com/products/docker-desktop/. Pick **Apple Chip** or **Intel Chip** to match your Mac ( → About This Mac).
2. Git is usually already installed. If `git --version` asks to install developer tools, say yes.
3. Open Docker Desktop once and wait for **Engine running**.

### Linux (Ubuntu)
```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER     # then log out and log back in
sudo apt install -y git
```

### Check it worked
Open **Git Bash** (Windows) or **Terminal** (Mac/Linux) and run:

```bash
docker version            # should show both "Client" and "Server" sections
docker compose version    # should print v2.x
git --version
```

If `docker version` shows an error under *Server*, Docker Desktop isn't running yet. Start it and wait.

---

## Step 2 — Get the code

```bash
cd ~                                   # or any folder you like, e.g. C:\code on Windows
git clone <REPO-URL> devops-ai-playbook
cd devops-ai-playbook/projects/telugu-pickles
```

> No Git? On the GitHub page click **Code → Download ZIP** and unzip it.
> Then open Git Bash or Terminal inside the `projects/telugu-pickles` folder.

> **Windows tip:** keep the folder path short, with no OneDrive folders (for example `C:\code\devops-ai-playbook`).
> OneDrive syncing can lock files while Docker is building.

---

## Step 3 — Start the store

**Full start** (store + Prometheus + Grafana). Recommended:

```bash
docker compose up -d --build
```

**Lite start** (store only, for 4 GB laptops):

```bash
docker compose up -d --build frontend
```

What happens:
1. Docker downloads the base images: Node.js, nginx, PostgreSQL, Prometheus and Grafana.
2. Docker builds the 7 Telugu Pickles images from the source code.
3. The containers start. Each service creates its own database and loads the 36 pickles and a demo user. **You don't need to run any SQL.**

The first run takes **5–15 minutes**, depending on your internet speed. Later runs take seconds.

---

## Step 4 — Check that it is healthy

```bash
docker compose ps
```

Wait until every app container shows **(healthy)**. This takes about 30 seconds after starting. Prometheus and Grafana don't show a health status, and that's normal.

```
NAME          STATUS
tp-auth       Up 40 seconds (healthy)
tp-cart       Up 40 seconds (healthy)
tp-catalog    Up 40 seconds (healthy)
tp-frontend   Up 39 seconds (healthy)
tp-gateway    Up 39 seconds (healthy)
tp-order      Up 39 seconds (healthy)
tp-payment    Up 40 seconds (healthy)
tp-postgres   Up 45 seconds (healthy)
...
```

Now open these in your browser:

| URL | What it is | Login |
|---|---|---|
| **http://localhost:3000** | The pickle store | `demo@telugupickles.in` / `Pickle@123`, or click **Use demo account** |
| http://localhost:8080/api/health | Health of every service as JSON | — |
| http://localhost:9090 | Prometheus (raw metrics) | — |
| http://localhost:3001 | Grafana dashboard | `admin` / `admin` (skip the password change) |

---

## Step 5 — Run the automatic test (smoke test)

This script runs 25 checks. It browses the catalogue, logs in, adds to the cart, places an order, checks that stock went down, and cancels the order.

```bash
./scripts/smoke-test.sh
```

Expected last line:

```
Result: 25 passed, 0 failed
```

> Windows: run it in **Git Bash**, not PowerShell or CMD.
> If you see `Permission denied`, run `bash scripts/smoke-test.sh` instead.

---

## Step 6 — Things to try

1. **Shop:** open http://localhost:3000. Filter **Veg / Non-Veg**, search "gongura", open a pickle, choose 250 g / 500 g / 1 kg, add to cart.
2. **Guest cart merge:** add items *before* logging in, then log in. Your guest items move into your account cart.
3. **Checkout:** pay with UPI, Card or Cash on Delivery. Orders of ₹999 or more ship free.
4. **Orders:** open **My Orders**, open an order, and cancel it. The stock goes back to the catalogue.
5. **Watch it live:** open Grafana (http://localhost:3001) while you shop. You'll see requests, latency and orders per minute move.
6. **Break it on purpose (AIOps preview):** make half of all payments fail:
   ```bash
   PAYMENT_DECLINE_RATE=0.5 docker compose up -d payment-service
   ```
   Place a few orders. Some fail with "Payment declined", and the reserved stock is released. Turn it off again:
   ```bash
   docker compose up -d payment-service
   ```
   Other fault switches are listed in [README.md](README.md#fault-injection-aiops-demo).

---

## Useful commands

All of these run from the `projects/telugu-pickles` folder.

| I want to… | Command |
|---|---|
| See all containers | `docker compose ps` |
| Read one service's logs | `docker compose logs order-service` |
| Follow logs live (Ctrl+C to stop) | `docker compose logs -f gateway order-service payment-service` |
| Trace one request across services | Copy the `requestId` from any log line, then `docker compose logs \| grep <requestId>` |
| Restart one service | `docker compose restart cart-service` |
| Rebuild after changing code | `docker compose up -d --build` |
| Look inside a database | `docker exec -it tp-postgres psql -U postgres -d catalog_db` then `select slug, stock_grams from products;` and `\q` to quit |
| Databases available | `auth_db`, `catalog_db`, `cart_db`, `orders_db`, `payments_db` |
| Resource usage | `docker stats` |

### Optional: edit the website with live reload
This needs **Node.js 22** (https://nodejs.org). Keep the Docker stack running, then:

```bash
cd frontend
npm install
npm run dev          # open http://localhost:5173; changes show instantly
```

### Optional: run the backend unit tests
```bash
cd services
npm ci
npm test
```

---

## Stop, restart, reset

```bash
docker compose stop          # pause everything (data kept)
docker compose start         # resume
docker compose down          # remove containers (data kept in the volume)
docker compose down -v       # remove containers AND data, for a fresh start with fresh demo data
```

To free all disk space used by this project:

```bash
docker compose down -v --rmi all
```

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `Cannot connect to the Docker daemon` / `error during connect` | Docker Desktop isn't running. Start it and wait for **Engine running**. |
| `port is already allocated` / `address already in use` | Another app uses that port. Find it: Windows `netstat -ano \| findstr :3000`, Mac/Linux `lsof -i :3000`. Close that app, **or** change the left-hand number in `docker-compose.yml` (for example `"3005:80"`) and open http://localhost:3005. |
| Home page loads but other pages are blank | Your browser is using an old cached copy. Press **Ctrl+Shift+R** (Mac: **Cmd+Shift+R**). Make sure you have the latest code (`git pull`), then `docker compose up -d --build`. |
| `$'\r': command not found` when running a `.sh` script | Windows changed the line endings. Run `git config --global core.autocrlf input`, delete the folder and clone again. (The repo's `.gitattributes` prevents this on fresh clones.) |
| A container keeps restarting or is `(unhealthy)` | Read its logs, for example `docker compose logs catalog-service`. Most often Postgres was still starting; it fixes itself within a minute. |
| `npm ERR!` / `network timeout` during build | Your internet or a college proxy blocked npm. Retry `docker compose build`, or try a phone hotspot. |
| Build is very slow or the laptop freezes | Use the **lite start** (Step 3). On Windows, close other heavy apps. You can also cap WSL memory with a `C:\Users\<you>\.wslconfig` file containing `[wsl2]` and `memory=4GB`. |
| `no space left on device` | Run `docker system prune` (removes stopped containers and unused images). |
| Login says "Invalid email or password" for the demo account | Check the spelling: `demo@telugupickles.in` / `Pickle@123` (capital P). If you changed data, `docker compose down -v` and start again. |
| Grafana dashboard is empty | Wait 30–60 seconds and click around the store. Prometheus needs a few scrapes before graphs appear. |

Still stuck? Run these and share the output with your instructor:

```bash
docker compose ps
docker compose logs --tail=50
```

---

## What's next

Once it runs locally, the same images go to the cloud:
**push to Amazon ECR → create EKS with Terraform → deploy with Argo CD → AIOps with Bedrock**.
Step-by-step: [docs/CICD-EKS-GUIDE.md](../../docs/CICD-EKS-GUIDE.md). Architecture: [docs/telugu-pickles-system-design.html](../../docs/telugu-pickles-system-design.html) (open it in a browser).
