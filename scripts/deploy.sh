#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../terraform"

terraform init -upgrade
terraform validate
terraform plan -out=tfplan
terraform apply -auto-approve tfplan

echo ""
echo "=========================================="
echo "  Deploy completo"
echo "=========================================="
terraform output
echo ""
echo "IMPORTANTE: revisa tu Gmail para confirmar el email de verificación de SES."
