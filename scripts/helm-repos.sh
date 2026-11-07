#!/usr/bin/env bash
# Register the Helm chart repositories used by the AKS bootstrap.
# Safe to run repeatedly before installing the platform charts.
set -euo pipefail
helm repo add ingress-nginx       https://kubernetes.github.io/ingress-nginx --force-update >/dev/null
helm repo add argo                 https://argoproj.github.io/argo-helm --force-update >/dev/null
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update >/dev/null
helm repo update >/dev/null
echo "Helm repositories ready: ingress-nginx, argo, prometheus-community"
