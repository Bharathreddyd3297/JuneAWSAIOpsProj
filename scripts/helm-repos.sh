#!/usr/bin/env bash
# Register the Helm chart repositories used by projects/Infrastructure.
# The Terraform Helm provider reads the local Helm repo cache; without it some
# machines fail with "no cached repo found". Safe to run any number of times.
set -euo pipefail
helm repo add argo                 https://argoproj.github.io/argo-helm --force-update >/dev/null
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update >/dev/null
helm repo add metrics-server       https://kubernetes-sigs.github.io/metrics-server/ --force-update >/dev/null
helm repo add eks                  https://aws.github.io/eks-charts --force-update >/dev/null
helm repo add external-dns         https://kubernetes-sigs.github.io/external-dns/ --force-update >/dev/null
helm repo update >/dev/null
echo "Helm repositories ready: argo, prometheus-community, metrics-server, eks, external-dns"
