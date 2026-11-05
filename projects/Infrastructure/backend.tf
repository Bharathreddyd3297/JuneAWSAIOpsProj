# Remote state in S3, shared by your laptop and GitHub Actions.
# The bucket is created by ./bootstrap and passed at init time:
#
#   terraform init -backend-config="bucket=telugu-pickles-tfstate-<ACCOUNT_ID>"
#
# use_lockfile = S3-native state locking (Terraform >= 1.10, no DynamoDB table needed),
# so a laptop apply and a pipeline apply can never run at the same time.
terraform {
  backend "s3" {
    key          = "telugu-pickles/infrastructure.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
