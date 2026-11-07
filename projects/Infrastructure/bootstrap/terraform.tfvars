# EDIT for your fork: owner/repository on GitHub
github_repository = "YOUR-GITHUB-USER/YOUR-REPO"

# Numeric IDs GitHub puts in its OIDC token (repo:OWNER@OWNER_ID/REPO@REPO_ID:...).
# Get them with:
#   curl -s https://api.github.com/repos/OWNER/REPO | python -c "import sys,json;r=json.load(sys.stdin);print(r['owner']['id'],r['id'])"
github_owner_id      = "YOUR_OWNER_ID"
github_repository_id = "YOUR_REPO_ID"

# true = create the GitHub OIDC provider (new account). Set false if
# "aws iam list-open-id-connect-providers" already lists token.actions.githubusercontent.com
create_github_oidc_provider = true

# Your GoDaddy domain (e.g. "telugupickles.in"). Leave "" until you are ready.
domain_name = ""
