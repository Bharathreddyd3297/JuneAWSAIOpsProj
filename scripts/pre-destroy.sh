#!/usr/bin/env bash
# Run BEFORE `terraform destroy` (the Infrastructure workflow does this automatically).
#
# The shop's Application Load Balancer and the Postgres EBS volume are created by
# controllers running inside EKS, not by Terraform. If the cluster is destroyed first,
# they are orphaned: the ALB blocks VPC deletion and the volume keeps costing money.
#
#   ./scripts/pre-destroy.sh [cluster-name] [region]
set -uo pipefail
CLUSTER="${1:-telugu-pickles-eks}"
REGION="${2:-us-east-1}"

if ! aws eks describe-cluster --name "$CLUSTER" --region "$REGION" >/dev/null 2>&1; then
  echo "Cluster $CLUSTER not found in $REGION - nothing to clean up."
  exit 0
fi
aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" >/dev/null

echo "1/4 Deleting the Argo CD application (cascades to Deployments, Services, the shop Ingress)..."
kubectl -n argocd delete application telugu-pickles --wait=true --timeout=10m 2>/dev/null || echo "    (no application)"

echo "2/4 Deleting remaining Ingresses (Argo CD / Grafana when a domain is used)..."
kubectl delete ingress --all --all-namespaces --wait=true --timeout=5m 2>/dev/null || true

echo "3/4 Deleting the Postgres volume claim (EBS volume)..."
kubectl -n telugu-pickles delete statefulset --all --wait=true --timeout=3m 2>/dev/null || true
kubectl -n telugu-pickles delete pvc --all --wait=true --timeout=5m 2>/dev/null || true

echo "4/4 Waiting until AWS has removed the load balancer and volumes..."
for _ in $(seq 1 40); do
  albs=0
  for arn in $(aws elbv2 describe-load-balancers --region "$REGION" --query 'LoadBalancers[].LoadBalancerArn' --output text 2>/dev/null); do
    owner=$(aws elbv2 describe-tags --region "$REGION" --resource-arns "$arn" \
      --query "TagDescriptions[0].Tags[?Key=='elbv2.k8s.aws/cluster'].Value | [0]" --output text 2>/dev/null)
    [ "$owner" = "$CLUSTER" ] && albs=$((albs + 1))
  done
  pvs=$(kubectl get pv --no-headers 2>/dev/null | grep -c telugu-pickles || true)
  if [ "$albs" = 0 ] && [ "$pvs" = 0 ]; then
    echo "    clean - safe to run terraform destroy"
    exit 0
  fi
  echo "    still deleting: $albs load balancer(s), $pvs volume(s)..."
  sleep 15
done
echo "WARNING: timed out waiting. Check EC2 -> Load Balancers / Volumes in the console after destroy."
exit 0
