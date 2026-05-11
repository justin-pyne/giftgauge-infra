# scripts/bring-up.sh
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> Terraform apply"
(cd terraform && terraform apply -auto-approve)

echo "==> Wait 30s for cluster API stabilization"
sleep 30

echo "==> Update kubeconfig"
aws eks update-kubeconfig --region us-east-1 --name giftgauge-eks

echo "==> Install all Helm releases"
helm upgrade --install giftgauge ./helm/giftgauge -n dev -f envs/dev/values.yaml --wait --timeout 10m
helm upgrade --install giftgauge ./helm/giftgauge -n qa  -f envs/qa/values.yaml  --wait --timeout 10m
helm upgrade --install giftgauge ./helm/giftgauge -n prod-blue  -f envs/prod-blue/values.yaml  -f envs/prod-active-color.yaml --wait --timeout 10m
helm upgrade --install giftgauge ./helm/giftgauge -n prod-green -f envs/prod-green/values.yaml -f envs/prod-active-color.yaml --wait --timeout 10m

echo "==> All deployed. Wait ~5min for cert-manager to issue all certs, then test:"
echo "    curl https://dev.justinpyne.xyz/api/profile/health"
echo "    curl https://qa.justinpyne.xyz/api/profile/health"
echo "    curl https://app.justinpyne.xyz/api/profile/health"
echo "    curl https://prod-blue.justinpyne.xyz/api/profile/health"
echo "    curl https://prod-green.justinpyne.xyz/api/profile/health"