# EDIT for your fork: owner/repository on GitHub
github_repository = "Bharathreddyd3297/JuneAWSAIOpsProj"

# Numeric IDs GitHub puts in its OIDC token (repo:OWNER@OWNER_ID/REPO@REPO_ID:...).
# Get them with:
#   curl -s https://api.github.com/repos/OWNER/REPO | python -c "import sys,json;r=json.load(sys.stdin);print(r['owner']['id'],r['id'])"
github_owner_id      = "217679465"
github_repository_id = "1446461087"

# This AWS account already has the GitHub OIDC provider -> reuse it.
# New AWS account? set to true.
create_github_oidc_provider = false

# Your GoDaddy domain (e.g. "telugupickles.in"). Leave "" until you are ready.
domain_name = ""
