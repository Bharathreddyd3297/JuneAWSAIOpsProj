# GitHub Actions Pipelines

Three workflows live in [`.github/workflows/`](../../.github/workflows/):

| File | Name in the Actions tab | Purpose |
|---|---|---|
| `security.yml` | **Security Scan** | Find leaked secrets and known vulnerabilities (Gitleaks + Trivy) |
| `infra.yml` | **Infrastructure** | Create, update or destroy AWS with Terraform |
| `ci.yml` | **App CI** | Test, build, scan and push the 7 images, then hand over to Argo CD |

```
                          ┌──────────── Security Scan (reusable) ────────────┐
                          │ Gitleaks: full git history                       │
                          │ Trivy fs: npm CVEs + secrets   Trivy config: IaC │
                          └───────────────┬───────────────────┬──────────────┘
                                          │ called first by   │
          projects/Infrastructure/** ─► Infrastructure        App CI ◄─ projects/telugu-pickles/**
                                          │                   │
                                plan ─► apply (main)      test ─► build ×7 ─► Trivy image ─► push ECR
                                          │                                         │
                                          ▼                                         ▼
                                AWS: VPC, EKS, ECR,                   bot commit: gitops/kustomization.yml
                                Argo CD, Grafana, ...                            │
                                                                                 ▼
                                                                    Argo CD syncs the cluster
```

---

## How GitHub logs in to AWS (OIDC)

No AWS keys are stored in GitHub. Each job that needs AWS:

1. asks GitHub for a short-lived **OIDC token** that says "I am repo X, branch Y" (`permissions: id-token: write`);
2. `aws-actions/configure-aws-credentials` swaps that token for **temporary AWS credentials** of the role in the `AWS_ROLE_ARN` secret;
3. AWS only agrees if the role's trust policy matches the token's `sub` claim. The role is created by `projects/Infrastructure/bootstrap` and trusts **this repository only**.

> GitHub sends `sub` in one of two formats: `repo:OWNER/REPO:ref:refs/heads/main`, or the immutable form `repo:OWNER@OWNER_ID/REPO@REPO_ID:ref:...`.
> The bootstrap trusts both, so set `github_owner_id` and `github_repository_id` in `bootstrap/terraform.tfvars`.

## Secrets and variables

| Kind | Name | Required | Used by | Notes |
|---|---|---|---|---|
| Secret | `AWS_ROLE_ARN` | yes, for anything in AWS | Infrastructure, App CI | Output `github_actions_role_arn` of the bootstrap |
| Variable | `AWS_REGION` | no | both | Default `us-east-1` |
| Variable | `TF_STATE_BUCKET` | no | Infrastructure | Default `telugu-pickles-tfstate-<account-id>` |
| Built-in | `GITHUB_TOKEN` | automatic | App CI deploy job | Lets the bot commit image tags; nothing to add |

**Without `AWS_ROLE_ARN` nothing fails.** Jobs that need AWS are skipped with a notice, while scans, tests and builds still run.

---

## 1. Security Scan — `security.yml`

**Runs on:** every pull request, pushes to `main` (except the bot's tag commits), every Monday at 03:30 UTC, manually, and as the first job of the other two workflows.
**Needs:** no secrets.

| Job | Tool | Checks | Fails the run when |
|---|---|---|---|
| `gitleaks` | Gitleaks 8.30.1, downloaded and checksum-verified | every commit in history for keys, tokens and passwords | anything is found that isn't allowlisted in [`.gitleaks.toml`](../../.gitleaks.toml) |
| `trivy` | Trivy 0.76.1, pinned by image digest | `package-lock.json` CVEs + secrets in files | a **CRITICAL** CVE that has a fixed version |
| `trivy` | Trivy `config` | Kubernetes YAML, Terraform, Dockerfiles | never (report only) |

Results also go to **Security → Code scanning** as SARIF. Trivy downloads its vulnerability database from ECR Public, which avoids GHCR rate limits.

**Why Gitleaks scans the whole history:** a secret removed in a later commit is still in the repository and should be treated as leaked. Rotate it, don't just delete it.

---

## 2. Infrastructure — `infra.yml`

**Runs on:**
- **pull requests:** changes under `projects/Infrastructure/**` (not `bootstrap/`) or to `infra.yml`;
- **pushes to `main`:** the same paths;
- **manual runs:** with an action of `plan`, `apply` or `destroy`.

| Trigger | security | plan | apply | destroy |
|---|---|---|---|---|
| Pull request | ✔ | ✔ (shown in run summary) | — | — |
| Push to `main` | ✔ | ✔ | ✔ | — |
| Manual: `plan` | ✔ | ✔ | — | — |
| Manual: `apply` | ✔ | ✔ | ✔ | — |
| Manual: `destroy` + confirm `destroy` | ✔ | ✔ | — | ✔ |

### Jobs

**plan**
- **Setup:** `setup-terraform` 1.16.6, AWS login, and `scripts/helm-repos.sh`, which registers the Helm chart repos the provider needs.
- **Init:** `terraform init -backend-config=bucket=…` points at the shared S3 state.
- **Checks:** `fmt -check`, `validate`, then `plan`, with a summary of the plan in the run page.

**apply**
- **When:** runs after plan succeeds, in the GitHub environment **`production`**. Add *Required reviewers* there to make it wait for your click.
- **Fresh plan:** re-plans and applies in the same job. Plan files contain generated passwords, and artifacts of a public repo are downloadable, so the plan is never uploaded.
- **Session length:** AWS session of 2 hours, because the first EKS creation plus Helm installs takes about 30 minutes.
- **Summary:** prints the cluster, the `kubectl` command, the shop URL, the Argo CD status and the log group.

**destroy**
1. Runs [`scripts/pre-destroy.sh`](../../scripts/pre-destroy.sh). It deletes the Argo CD application, the Ingresses and the Postgres volume claim, then waits until AWS has removed the load balancer and the EBS volume.
2. Then runs `terraform destroy`.

Without step 1 the controller-created ALB would block VPC deletion, and the EBS volume would keep costing money.

### Concurrency and locking
- **Workflow concurrency group `terraform-<repo>`:** two runs never overlap, and a new run queues instead of cancelling a running apply.
- **S3 state locking (`use_lockfile = true`):** a laptop `terraform apply` and a pipeline run can't corrupt the state.

---

## 3. App CI — `ci.yml`

**Runs on:**
- **pull requests:** changes under `projects/telugu-pickles/**` or to `ci.yml`;
- **pushes to `main`:** the same paths;
- **manual runs.**

`gitops/` is deliberately **not** a trigger, so the bot's own tag commit can't start another run.

| Job | What happens | On PRs | On `main` |
|---|---|---|---|
| `security` | the reusable Security Scan | ✔ | ✔ |
| `test` | `npm ci && npm test` (backend), `npm run build` (frontend), Node 22 | ✔ | ✔ |
| `aws` | checks for `AWS_ROLE_ARN`, logs in, works out the ECR registry `<acct>.dkr.ecr.<region>.amazonaws.com` | ✔ | ✔ |
| `build` (×7 in parallel) | Docker build (linux/amd64, GHA layer cache) → **Trivy image scan before pushing** (fails on fixable CRITICAL) → push `:<commit-sha>` to ECR | build + scan only | build + scan + **push** |
| `deploy` | checks all 7 images exist in ECR → `yq` sets `newName`/`newTag` in `gitops/kustomization.yml` → commits `deploy: telugu-pickles <sha>` → pushes to `main` | — | ✔ |

**Image tag = full git commit SHA,** so every running pod can be traced to the exact commit that built it.

**Safety nets:**
- If an ECR repository doesn't exist yet (infrastructure not created), the push step warns and the deploy job does nothing. No red run.
- The deploy job retries `git pull --rebase` + push up to 3 times in case someone pushed meanwhile.

---

## Typical flows

| You do | What runs | Result |
|---|---|---|
| Open a PR changing app code | Security, test, build + scan | Green or red check on the PR; nothing deployed |
| Merge that PR | App CI on `main` | New images in ECR → bot commit → Argo CD rolls out within ~1 min |
| Change `terraform.tfvars` (for example `max_size`) | Infrastructure on `main` | Plan, then apply; node group resized |
| Change `gitops/k8s/...` directly | Nothing in Actions | Argo CD applies it within ~1 min (Git is the source of truth) |
| Actions → Infrastructure → `destroy` | pre-destroy + destroy | Everything except the bootstrap is removed |

## When something fails

| Message | Meaning |
|---|---|
| `Not authorized to perform sts:AssumeRoleWithWebIdentity` | The role's trust policy doesn't match the token. Check `github_repository`/IDs in the bootstrap tfvars and re-apply it. CloudTrail event `AssumeRoleWithWebIdentity` shows the `sub` GitHub sent. |
| `Error acquiring the state lock` | Another Terraform run holds the lock. Wait, or `terraform force-unlock <id>` if it crashed. |
| `no cached repo found` | Helm repo cache missing. The workflow runs `scripts/helm-repos.sh`; on a laptop, run it yourself. |
| Gitleaks: `leaks found` | A secret is in history. Rotate it first, then clean up. |
| Trivy: `Total: n (CRITICAL: n)` | Upgrade the package or base image to the *Fixed Version* shown. |
| Deploy: `push declined` | Branch protection blocks the bot. Allow `github-actions[bot]` to push to `main`. |
