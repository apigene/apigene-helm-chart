#!/usr/bin/env bash
# Post-apply verification for the AWS EKS Terraform example.
#
# Run from terraform/examples/aws-eks after terraform apply:
#   ./scripts/test-terraform-aws.sh
#
# Or set TF_DIR to the example directory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TF_DIR="${TF_DIR:-${ROOT}/terraform/examples/aws-eks}"

require() {
  command -v "$1" >/dev/null 2>&1 || { echo "error: $1 is required" >&2; exit 1; }
}

require terraform
require kubectl
require curl
require aws

cd "${TF_DIR}"

APIGENE_URL="$(terraform output -raw apigene_url)"
CLUSTER_NAME="$(terraform output -raw cluster_name)"
NAMESPACE="$(terraform output -raw namespace)"
AWS_REGION="${AWS_REGION:-eu-central-1}"

echo "Configuring kubectl for cluster ${CLUSTER_NAME}..."
aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}" >/dev/null

echo "Checking cluster nodes..."
kubectl get nodes

echo "Checking Apigene pods..."
kubectl get pods -n "${NAMESPACE}"

echo "Checking cert-manager certificate..."
if kubectl get certificate -n "${NAMESPACE}" >/dev/null 2>&1; then
  kubectl wait --for=condition=ready certificate -n "${NAMESPACE}" --all --timeout=600s || true
  kubectl get certificate -n "${NAMESPACE}"
fi

echo "Checking ingress..."
kubectl get ingress -n "${NAMESPACE}"

echo "Running smoke tests against ${APIGENE_URL}..."
BASE_URL="${APIGENE_URL}" "${ROOT}/scripts/smoke.sh"

echo "Running integration tests..."
BASE_URL="${APIGENE_URL}" "${ROOT}/tests/integration.sh"

echo "AWS Terraform verification completed successfully."
echo "Apigene URL: ${APIGENE_URL}"
