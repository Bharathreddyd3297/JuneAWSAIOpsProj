# Telugu Pickles — AWS infrastructure inputs
region   = "us-east-1" # us-east-1 has the widest Amazon Bedrock model + Agents coverage (AIOps phase)
vpc_name = "telugu-pickles-vpc"
vpc_cidr = "10.1.0.0/16"

subnets = [
  { name = "subnet-1", cidr_block = "10.1.1.0/24", availability_zone = "us-east-1a" },
  { name = "subnet-2", cidr_block = "10.1.2.0/24", availability_zone = "us-east-1b" },
  { name = "subnet-3", cidr_block = "10.1.3.0/24", availability_zone = "us-east-1c" },
]

cluster_name    = "telugu-pickles-eks"
node_group_name = "telugu-pickles-nodes"

# m7i-flex.large = 2 vCPU / 8 GiB, max 29 pods per node.
# App (10) + ArgoCD (7) + monitoring (7) + kube-system (~11) = ~35 pods -> needs 2 nodes.
instance_types = ["m7i-flex.large"]
capacity_type  = "ON_DEMAND"
desired_size   = 2
min_size       = 2
max_size       = 3
disk_size      = 30

repositories = [
  "telugu-pickles/frontend",
  "telugu-pickles/gateway",
  "telugu-pickles/auth-service",
  "telugu-pickles/catalog-service",
  "telugu-pickles/cart-service",
  "telugu-pickles/order-service",
  "telugu-pickles/payment-service",
]
