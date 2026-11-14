#!/usr/bin/env bash
# Register the Helm chart repositories used by projects/AzureInfrastructure.
# The Terraform Helm provider reads the local Helm repo cache; without it some
# machines fail with "no cached repo found". Safe to run any number of times.
set -euo pipefail
helm repo add argo                 https://argoproj.github.io/argo-helm --force-update >/dev/null
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update >/dev/null
helm repo add ingress-nginx        https://kubernetes.github.io/ingress-nginx --force-update >/dev/null
helm repo update >/dev/null
echo "Helm repositories ready: argo, prometheus-community, ingress-nginx"
