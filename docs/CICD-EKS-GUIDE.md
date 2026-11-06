# Telugu Pickles: From `git push` to a Running Shop on EKS

This guide continues from [running the app locally](../projects/telugu-pickles/LOCAL-SETUP.md). At the end:

- **GitHub Actions** creates the AWS infrastructure with Terraform: VPC, EKS, ECR, Argo CD, Prometheus/Grafana and CloudWatch logging.
- **GitHub Actions** tests, scans (Gitleaks + Trivy), builds and pushes the 7 images to ECR.
- **Argo CD** notices the new image tags in Git and deploys them to Kubernetes, with no `kubectl apply` by you.
- You open the shop, Argo CD and the Grafana dashboards.

**Time:** about 1 hour 15 minutes the first time, of which about 30 minutes is waiting for EKS.
Reference docs (what each pipeline, resource and Argo CD setting does): [docs/reference/](reference/README.md)

**Cost:** about **$0.35 per hour** while the cluster exists. [Destroy it](#step-12--destroy-everything-stop-the-bill) when you finish.

---

## The big picture

```
 you: git push
     │
     ├── projects/Infrastructure/**  ──► Infrastructure workflow
     │                                    Security scan → terraform plan → terraform apply
     │                                    creates VPC, EKS, ECR, Argo CD, Grafana, CloudWatch,
     │                                    and the Argo CD Application that watches gitops/
     │
     └── projects/telugu-pickles/**  ──► App CI workflow
                                          Security scan + unit tests
                                          → build 7 images → Trivy image scan
                                          → push to ECR (tag = commit SHA)
                                          → bot commits new tags to gitops/kustomization.yml
                                                         │
                                Argo CD (inside EKS) ◄───┘ polls Git every 60 s
                                          → rolls out new pods → shop on an AWS load balancer
                                          → Prometheus scrapes /metrics → Grafana dashboard
                                          → Fluent Bit ships logs → CloudWatch Logs
```

| Workflow file | Runs when | What it needs |
|---|---|---|
| [`security.yml`](../.github/workflows/security.yml) | every PR / push, weekly, and as step 1 of the other two | nothing |
| [`infra.yml`](../.github/workflows/infra.yml) | changes under `projects/Infrastructure/`, or manually | `AWS_ROLE_ARN` secret |
| [`ci.yml`](../.github/workflows/ci.yml) | changes under `projects/telugu-pickles/`, or manually | `AWS_ROLE_ARN` secret (only for push + deploy) |

Pull requests run the scans, tests and a Terraform **plan** only. Nothing is pushed or applied until code reaches `main`.

---

## Step 0 — Tools on your laptop (one time)

| Tool | Check | Install |
|---|---|---|
| Git | `git --version` | https://git-scm.com |
| AWS CLI v2 | `aws --version` | https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html |
| Terraform ≥ 1.10 | `terraform version` | https://developer.hashicorp.com/terraform/install |
| kubectl | `kubectl version --client` | https://kubernetes.io/docs/tasks/tools/ |
| Helm 3 | `helm version` | https://helm.sh/docs/intro/install/ |

> Windows: run every command in **Git Bash**.

Sign in to AWS with a user that has administrator rights. Use **us-east-1**:

```bash
aws configure                      # Access key, secret key, region us-east-1, output json
aws sts get-caller-identity        # note the "Arn": you need it in Step 1
```

---

## Step 1 — Fork the repo and edit 3 values

1. On GitHub, click **Fork**, then clone **your fork**:
   ```bash
   git clone https://github.com/<you>/<repo>.git
   cd <repo>
   ```
2. **`projects/Infrastructure/bootstrap/terraform.tfvars`**
   ```hcl
   github_repository           = "<you>/<repo>"   # exactly as on GitHub
   github_owner_id             = "<owner id>"     # numbers, see below
   github_repository_id        = "<repo id>"
   create_github_oidc_provider = true             # false only if your AWS account already has it
   domain_name                 = ""               # keep empty for now
   ```
   GitHub's login token names your repo by **numeric IDs** (`repo:you@123/repo@456:...`). Get yours (public API, no login):
   ```bash
   curl -s https://api.github.com/repos/<you>/<repo> | python -c "import sys,json;r=json.load(sys.stdin);print('owner id:',r['owner']['id'],' repo id:',r['id'])"
   ```
   To check whether the GitHub provider already exists, run `aws iam list-open-id-connect-providers`. If you see `token.actions.githubusercontent.com`, set it to `false`.
3. **`projects/Infrastructure/terraform.tfvars`**
   ```hcl
   cluster_admin_arns = ["<the Arn from aws sts get-caller-identity>"]   # lets YOUR kubectl in
   gitops_repo_url    = "https://github.com/<you>/<repo>.git"           # what Argo CD deploys
   ```
   Your fork must be **public**, so Argo CD can read it without a password.

Commit these edits but **don't push yet**:

```bash
git add -A && git commit -m "Configure for my AWS account"
```

---

## Step 2 — Bootstrap (laptop, one time, about 1 minute)

GitHub Actions can't create the things it needs in order to log in, so you create them once from your laptop:

| Created | Why |
|---|---|
| S3 bucket `telugu-pickles-tfstate-<account-id>` | Terraform **remote state**, shared by your laptop and GitHub, with locking |
| IAM role `telugu-pickles-github-actions` | GitHub **logs in to AWS via OIDC**, so no AWS keys are stored in GitHub |
| (optional) Route 53 hosted zone | for your own domain, see [Step 10](#step-10--use-your-own-domain-godaddy--route-53) |

```bash
cd projects/Infrastructure/bootstrap
terraform init
terraform apply          # review: 7 resources to add, then type "yes"
terraform output         # keep this window open
```

Example output:

```
github_actions_role_arn = "arn:aws:iam::123456789012:role/telugu-pickles-github-actions"
state_bucket            = "telugu-pickles-tfstate-123456789012"
```

> The IAM role gets AdministratorAccess, and only workflows from **your repository** can assume it.
> That's a demo trade-off: Terraform creates IAM roles, VPCs and EKS. For production, use a narrower policy.

---

## Step 3 — GitHub settings (secrets and variables)

Open your fork: **Settings → Secrets and variables → Actions**.

### Required

| Type | Name | Value |
|---|---|---|
| **Secret** | `AWS_ROLE_ARN` | `github_actions_role_arn` from Step 2 |

That's the only secret. There are **no AWS access keys** and **no database passwords** in GitHub:
- **Database, JWT and Grafana passwords** are generated by Terraform and stored in the encrypted S3 state and in Kubernetes Secrets.
- **The code-pushing token** is GitHub's built-in `GITHUB_TOKEN`; you don't add it.

### Optional (tab "Variables")

| Variable | Default when unset | Set it when… |
|---|---|---|
| `AWS_REGION` | `us-east-1` | you deploy to another region (also change `region` in both tfvars) |
| `TF_STATE_BUCKET` | `telugu-pickles-tfstate-<account-id>` | you renamed the state bucket |

### Recommended repository settings

| Where | Setting | Why |
|---|---|---|
| Settings → Actions → General → Workflow permissions | *Read and write permissions* | lets the App CI bot commit new image tags (the workflow also asks for it explicitly) |
| Settings → Environments → **production** (created on the first run) | *Required reviewers: you* | makes `terraform apply` / `destroy` wait for your approval click |
| Settings → Branches | if you protect `main`, allow **github-actions[bot]** to push | otherwise the deploy commit is rejected |

> If `AWS_ROLE_ARN` is missing, nothing fails: the workflows still scan, test and build, and show a notice that AWS steps were skipped.

---

## Step 4 — Push and let the pipelines build everything

```bash
git push origin main
```

Open **Actions** in GitHub. On the first push both workflows start.

### 4a. Infrastructure workflow (about 30 minutes the first time)

1. **Security scan**: Gitleaks and Trivy (about 1 min).
2. **Terraform plan**: the run summary shows *Plan: 62 to add*.
3. **Terraform apply** creates, in this order:
   - VPC (3 public subnets), EKS 1.35 control plane (about 10 min) and 2 × m7i-flex.large nodes;
   - 7 ECR repositories;
   - Argo CD, **Argo Rollouts** (blue-green and canary), kube-prometheus-stack (Prometheus + Grafana), metrics-server, AWS Load Balancer Controller and Fluent Bit;
   - the `telugu-pickles` namespace and its Secret (generated passwords);
   - the **Argo CD Application** pointing at `gitops/` in your repository.

   When it finishes, the run **Summary** shows the cluster name and the `kubectl` command.

### 4b. App CI workflow (about 6 minutes)

1. Security scan and unit tests run in parallel.
2. Each of the 7 images is built, **scanned by Trivy (the build fails on fixable CRITICAL vulnerabilities)**, then pushed to ECR as `:<commit-sha>`.
3. **Deploy job**: the bot commits the new tags to `gitops/kustomization.yml` ("deploy: telugu-pickles abc1234").

> **First run only:** App CI usually finishes before EKS and ECR exist. Its deploy job then shows a warning and stops without failing.
> When the Infrastructure run is green, open **Actions → App CI → Run workflow** (branch `main`). This time it pushes the images and commits the tags.

---

## Step 5 — Watch Argo CD create the deployments

Connect `kubectl` to the cluster:

```bash
aws eks update-kubeconfig --name telugu-pickles-eks --region us-east-1
kubectl get nodes                      # 2 nodes, STATUS Ready
```

Watch the application become **Synced / Healthy**. Press Ctrl+C when it does:

```bash
kubectl -n argocd get application telugu-pickles -w
# NAME             SYNC STATUS   HEALTH STATUS
# telugu-pickles   Synced        Progressing
# telugu-pickles   Synced        Healthy
```

```bash
kubectl -n telugu-pickles get pods     # 11 pods Running (postgres-0, 2× frontend, 2× gateway, ...)
```

### Open the Argo CD UI

```bash
# password for user "admin"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo

kubectl -n argocd port-forward svc/argocd-server 8081:80
```

Open **http://localhost:8081** and log in as `admin` with that password. Click **telugu-pickles** to see the tree: Deployments → ReplicaSets → Pods, the StatefulSet, Services, the Ingress and the dashboard ConfigMap.
Every box shows its health. **App diff** shows what Git wants compared with what's running.

> Argo CD runs with `selfHeal: true`. Try `kubectl -n telugu-pickles scale deploy cart-service --replicas=0`. Within a minute Argo CD puts it back, because Git is the source of truth.

---

## Step 6 — Open the shop

```bash
kubectl -n telugu-pickles get ingress frontend
# NAME      CLASS  HOSTS  ADDRESS                                                    PORTS
# frontend  alb    *      k8s-telugupickles-1a2b3c4d5e-1234567890.us-east-1.elb.amazonaws.com   80
```

Open `http://<ADDRESS>` in your browser. **A new load balancer takes 2–3 minutes before it answers.** Log in with `demo@telugupickles.in` / `Pickle@123`.

Run the same 25 end-to-end checks you ran locally, this time against EKS:

```bash
cd projects/telugu-pickles
./scripts/smoke-test.sh "http://<ADDRESS>"      # Result: 25 passed, 0 failed
```

---

## Step 7 — Grafana dashboards

```bash
# password for user "admin"
kubectl -n monitoring get secret kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo
#   (or, from projects/Infrastructure:  terraform output -raw grafana_admin_password)

kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3001:80
```

Open **http://localhost:3001**, log in as `admin`, then go to **Dashboards → Telugu Pickles**.

| Panel | Shows |
|---|---|
| Request rate / error rate / p95 latency | per service, from each pod's `/metrics` (RED method) |
| Orders placed, revenue, payment results | business metrics (`tp_orders_placed_total`, `tp_payments_total`, …) |
| Pods / CPU / memory | from kube-state-metrics + cAdvisor |

Generate traffic and watch the graphs move. Use the shop for a minute or run the smoke test 3–4 times.
The other dashboards (**Kubernetes / Compute Resources / …**) come with kube-prometheus-stack.

Alert rules (from [`gitops/k8s/monitoring/servicemonitor.yml`](../gitops/k8s/monitoring/servicemonitor.yml)) are under **Alerting → Alert rules** in Grafana and at **Status → Rules** in Prometheus.

---

## Step 8 — CloudWatch logs and alarm

Fluent Bit (namespace `amazon-cloudwatch`) ships every Telugu Pickles container log line to the log group **`/eks/telugu-pickles/pods`**, kept for 7 days. Tomorrow's Bedrock AIOps agent reads from here.

```bash
aws logs tail /eks/telugu-pickles/pods --follow --since 10m     # Ctrl+C to stop
```

Console: **CloudWatch → Logs → Log Insights**. Pick `/eks/telugu-pickles/pods` and run:

```
fields @timestamp, data.service, data.level, data.msg, data.requestId
| filter data.level = "ERROR"
| sort @timestamp desc
| limit 50
```

Terraform also creates:
- a **metric filter** that counts `ERROR` lines and publishes them as **TeluguPickles → AppErrorCount**;
- an **alarm** `telugu-pickles-error-spike` that fires at more than 5 errors in 5 minutes (CloudWatch → Alarms).

Trigger it on purpose: in [`gitops/k8s/platform/config.yml`](../gitops/k8s/platform/config.yml) set `PAYMENT_DECLINE_RATE: "0.8"`, then commit and push. Argo CD applies it; restart the payment pods with `kubectl -n telugu-pickles rollout restart deploy payment-service`. Then run the smoke test a few times. Set it back to `"0"` afterwards.

---

## Step 9 — Make a change and watch continuous deployment

This is the loop you'll use every day:

1. Change something visible, for example the hero line in `projects/telugu-pickles/frontend/src/pages/Home.jsx`.
2. `git commit -am "Change hero text" && git push`
3. **Actions → App CI** goes green in about 6 minutes, and a bot commit `deploy: telugu-pickles <sha>` appears.
4. Within about 1 minute **Argo CD** shows *OutOfSync → Syncing*, and each service is released by its own strategy:
   - **frontend**, **blue-green**: the new version appears on **`http://<ALB>:8080`** while shoppers on `http://<ALB>` still see the old one. Argo CD shows *Suspended*.
     When you're happy, run **Actions → Release control → `frontend` → `promote`**.
   - **catalog-service**, **canary**: 25% of pods → automatic Prometheus error check → 50% → check → 100%. A bad version is rolled back automatically.
   - **the other services**: rolling update, pods replaced one by one with zero downtime.
5. Refresh the shop.

**Roll back** by reverting the bot commit: `git revert <deploy-commit> && git push`. Argo CD redeploys the previous images.

**Full blue-green and canary walkthrough, including a deliberately failing canary:** [reference/PROGRESSIVE-DELIVERY.md](reference/PROGRESSIVE-DELIVERY.md).

---

## Step 10 — Use your own domain (GoDaddy + Route 53)

Do this once the plain load-balancer URL works.

1. In `projects/Infrastructure/bootstrap/terraform.tfvars` set `domain_name = "yourdomain.com"`, then:
   ```bash
   cd projects/Infrastructure/bootstrap && terraform apply
   terraform output route53_name_servers      # 4 names like ns-123.awsdns-45.com
   ```
2. **GoDaddy:** My Products → your domain → **DNS** → **Nameservers** → **Change** → *I'll use my own nameservers*. Enter the 4 AWS nameservers and save.
   Changes usually apply within 30 minutes but can take up to 48 hours. Check with `nslookup -type=NS yourdomain.com`.
3. Once the nameservers show AWS, set `domain_name = "yourdomain.com"` in `projects/Infrastructure/terraform.tfvars`, commit and push.
   The Infrastructure workflow then:
   - issues a free **ACM certificate** for `yourdomain.com` and `*.yourdomain.com`, validated automatically through Route 53;
   - installs **ExternalDNS**, which creates the DNS records for you;
   - serves **https://shop.yourdomain.com**, **https://argocd.yourdomain.com** and **https://grafana.yourdomain.com** from one shared load balancer, redirecting HTTP to HTTPS.

> This moves the whole domain's DNS to Route 53 ($0.50 per month). If you use the domain for other things (email, another site), recreate those records in Route 53 first.

---

## Step 11 — AIOps with Amazon Bedrock (Kira and her agents)

The Infrastructure workflow also creates **Kira**, a multi-agent AIOps assistant in the Lambda `telugu-pickles-kira`.
- **Kira** is a supervisor model. She delegates to three **specialist agents**:
  - the **logs** agent, which reads CloudWatch Logs;
  - the **metrics** agent, which reads Prometheus;
  - the **deployment** agent, which reads Argo CD, Rollouts, pods and events.
- Every agent is a Bedrock **Converse** tool-use loop with read-only tools.
- When the CloudWatch error alarm fires, Kira writes a root-cause report and sends it to SNS (email).

1. **Models:** the default is Amazon Nova, which needs no approval. For Claude, see [Models](../projects/aiops-assistant/README.md#models).
2. **Optional email reports:** set `aiops_alert_email` in `terraform.tfvars`, push, and click the AWS confirmation mail.
3. **Chat:** `cd projects/aiops-assistant && pip install -r requirements.txt && streamlit run app.py`, then ask *"Is everything healthy?"*.
4. **Full demo:** ship a failing canary. Argo Rollouts rolls it back, the alarm fires, and Kira emails the incident report. See the
   [demo in the AIOps README](../projects/aiops-assistant/README.md#demo-failed-canary--automatic-rollback--automatic-ai-incident-report).

---

## Step 12 — Destroy everything (stop the bill)

**Option A, from GitHub:** **Actions → Infrastructure → Run workflow**, choose `destroy` and type `destroy` in the confirm box.

**Option B, from your laptop:**

```bash
cd projects/Infrastructure
terraform init -backend-config="bucket=$(cd bootstrap && terraform output -raw state_bucket)"
../../scripts/pre-destroy.sh telugu-pickles-eks us-east-1     # removes the load balancer + database volume first
terraform destroy                                             # about 15 min
```

`pre-destroy.sh` matters because the load balancer and the database disk are created by controllers inside Kubernetes, not by Terraform. Without it they're left behind, block the VPC deletion and keep costing money.

What stays (almost free): the bootstrap S3 bucket, the IAM role and, if you created it, the Route 53 zone. Re-running the Infrastructure workflow rebuilds everything, and App CI re-pushes the images.

---

## Security scanning (Gitleaks + Trivy)

| Scanner | Looks for | Fails the pipeline when |
|---|---|---|
| **Gitleaks** | API keys, tokens, passwords in **every commit ever** | any secret is found (allowlist: [`.gitleaks.toml`](../.gitleaks.toml)) |
| **Trivy fs** | known CVEs in `package-lock.json` dependencies, secrets in files | a **CRITICAL** CVE that already has a fix |
| **Trivy image** | CVEs in each built container (Alpine packages + Node modules) | a **CRITICAL** CVE that already has a fix, *before* the image is pushed |
| **Trivy config** | Kubernetes / Terraform / Dockerfile misconfigurations | never (report only) |

Results appear in the run log and under **Security → Code scanning** in your repo.

**If Gitleaks fails:** treat the secret as **already stolen**. Revoke or rotate it at the provider first, then remove it from the code. Deleting it in a new commit isn't enough, because it stays in git history. To try it locally:

```bash
docker run --rm -v "$PWD:/repo" zricethezav/gitleaks:v8.30.1 git /repo --config /repo/.gitleaks.toml --redact
```

**If Trivy fails on a CVE:** the log shows the package and the *Fixed Version*. Upgrade it (`npm install <pkg>@<fixed>` or bump the base image in the Dockerfile), push, and the gate passes.

---

## Troubleshooting

| Symptom | Cause → fix |
|---|---|
| `Not authorized to perform sts:AssumeRoleWithWebIdentity` | The role doesn't trust the identity GitHub sent. Check `github_repository`, `github_owner_id` and `github_repository_id` in bootstrap tfvars, and that the secret holds the right ARN. To see exactly what GitHub sent: `aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity --max-results 3`; the `userName` field is the `sub` claim. Fix it, re-apply the bootstrap, re-run. |
| `Error acquiring the state lock` | Another plan or apply is running (laptop or GitHub). Wait. If one crashed, run `terraform force-unlock <ID>` once. |
| `no cached repo found` (Helm) on your laptop | Run `./scripts/helm-repos.sh` once. |
| `kubectl`: `You must be logged in to the server (Unauthorized)` | Your IAM ARN isn't in `cluster_admin_arns`. Add it, push, and the Infrastructure workflow grants access. |
| Pods `ImagePullBackOff` | The images aren't in ECR yet. Run **App CI → Run workflow** on `main`. |
| Argo CD `OutOfSync` / `SyncFailed` | Open the app in the UI, then **Sync status → details**. Usually a YAML error in `gitops/`; check it with `kubectl kustomize gitops/`. |
| Ingress has no ADDRESS after 5 min | `kubectl -n kube-system logs deploy/aws-load-balancer-controller` |
| Deploy job: `push declined` / protected branch | Allow **github-actions[bot]** to push to `main` (Step 3). |
| Grafana dashboard empty | Wait 1–2 minutes and generate traffic. Check that **Status → Targets** in Prometheus lists `telugu-pickles` targets as UP. |
| No logs in CloudWatch | `kubectl -n amazon-cloudwatch logs ds/aws-for-fluent-bit` |
| `terraform destroy` stuck on subnets or VPC | A leftover load balancer. Run `scripts/pre-destroy.sh`, or delete the `k8s-telugupi…` load balancer in EC2, then destroy again. |

---

## What costs money

| Resource | Approx. per hour |
|---|---|
| EKS control plane | $0.10 |
| 2 × m7i-flex.large nodes | $0.19 |
| Application Load Balancer | $0.03 |
| EBS (2 × 30 GiB nodes + 10 GiB database), CloudWatch logs, ECR storage | < $0.02 |
| **Total** | **≈ $0.35 / hour ≈ $8.40 / day** |

The bootstrap leftovers (S3 state, IAM role) cost cents per month, and a Route 53 zone costs $0.50 per month.

---

**Next:** AIOps with Amazon Bedrock Agents + Lambda reading these CloudWatch logs and Prometheus metrics ([projects/aiops-assistant](../projects/aiops-assistant/README.md)).
