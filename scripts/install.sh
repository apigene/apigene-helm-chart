#!/usr/bin/env bash
# Apigene Helm one-line installer
#
#   curl -fsSL https://raw.githubusercontent.com/apigene/apigene-helm-chart/main/scripts/install.sh | bash
#
# Environment variables:
#   APIGENE_INSTALL_DIR     Clone location (default: ~/apigene-helm)
#   APIGENE_BRANCH          Git branch (default: main)
#   APIGENE_RELEASE_NAME    Helm release name (default: apigene)
#   APIGENE_NAMESPACE       Kubernetes namespace (default: apigene)
#   APIGENE_AUTH_SECRET     Auth secret (generated if unset)
#   APIGENE_HELM_EXTRA_ARGS Extra helm arguments (e.g. -f values-production.yaml)
#   APIGENE_SKIP_INSTALL    Set to 1 to clone/update only, skip helm install

set -euo pipefail

APIGENE_REPO="${APIGENE_REPO:-https://github.com/apigene/apigene-helm-chart.git}"
APIGENE_BRANCH="${APIGENE_BRANCH:-main}"
APIGENE_INSTALL_DIR="${APIGENE_INSTALL_DIR:-${HOME}/apigene-helm}"
APIGENE_RELEASE_NAME="${APIGENE_RELEASE_NAME:-apigene}"
APIGENE_NAMESPACE="${APIGENE_NAMESPACE:-apigene}"
APIGENE_SKIP_INSTALL="${APIGENE_SKIP_INSTALL:-0}"
EXTRA_ARGS="${APIGENE_HELM_EXTRA_ARGS:-}"

info()  { echo "  ·  $1"; }
ok()    { echo "  ✔  $1"; }
warn()  { echo "  !  $1"; }
err()   { echo "  ✘  $1" >&2; }
step()  { echo "  →  $1"; }
section() { echo ""; echo "━━ $1 ━━"; }

require_command() {
  local name="$1" hint="$2"
  if command -v "$name" >/dev/null 2>&1; then
    ok "$name available"
    return 0
  fi
  err "$name not found"
  info "$hint"
  return 1
}

check_kubectl_cluster() {
  local ctx server
  ctx="$(kubectl config current-context 2>/dev/null || true)"
  server="$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || true)"

  if [[ -z "${ctx}" ]]; then
    err "No kubectl context configured"
    info "Point kubectl at a cluster, e.g.:"
    info "  k3d cluster create apigene --agents 1 --wait"
    info "  # or: gcloud container clusters get-credentials ..."
    return 1
  fi

  info "kubectl context: ${ctx}"
  [[ -n "${server}" ]] && info "API server:      ${server}"

  if kubectl cluster-info >/dev/null 2>&1; then
    ok "Kubernetes cluster is reachable"
    return 0
  fi

  err "Kubernetes cluster unreachable"
  if [[ "${server}" == *"10.0.0."* ]] || [[ "${ctx}" == *k3d* ]]; then
    info "Your context may point at a deleted local cluster."
    info "Recreate one with: k3d cluster create apigene --agents 1 --wait"
    info "Or switch context:  kubectl config get-contexts"
  else
    info "Check VPN/network access and run: kubectl cluster-info"
  fi
  return 1
}

install_repo() {
  section "Install files"

  if [[ -d "${APIGENE_INSTALL_DIR}/.git" ]]; then
    step "Updating existing install at ${APIGENE_INSTALL_DIR}"
    git -C "${APIGENE_INSTALL_DIR}" fetch origin "${APIGENE_BRANCH}"
    git -C "${APIGENE_INSTALL_DIR}" checkout "${APIGENE_BRANCH}"
    git -C "${APIGENE_INSTALL_DIR}" pull --ff-only origin "${APIGENE_BRANCH}" || true
    ok "Repository updated"
  elif [[ -d "${APIGENE_INSTALL_DIR}" ]]; then
    err "Install directory exists but is not a git repo: ${APIGENE_INSTALL_DIR}"
    info "Remove it or set APIGENE_INSTALL_DIR to a different path."
    exit 1
  else
    step "Cloning into ${APIGENE_INSTALL_DIR}"
    git clone --branch "${APIGENE_BRANCH}" --depth 1 "${APIGENE_REPO}" "${APIGENE_INSTALL_DIR}"
    ok "Repository cloned"
  fi

  chmod +x "${APIGENE_INSTALL_DIR}/scripts/"*.sh 2>/dev/null || true
  chmod +x "${APIGENE_INSTALL_DIR}/tests/"*.sh 2>/dev/null || true
}

run_helm_install() {
  local chart_path="${APIGENE_INSTALL_DIR}/chart/apigene"
  local auth_secret="${APIGENE_AUTH_SECRET:-}"

  section "Helm install"

  if [[ -z "${auth_secret}" ]]; then
    if command -v openssl >/dev/null 2>&1; then
      auth_secret="$(openssl rand -hex 32)"
      echo ""
      warn "Generated APIGENE_AUTH_SECRET — save this for upgrades:"
      echo "  ${auth_secret}"
      echo ""
    else
      err "Set APIGENE_AUTH_SECRET or install openssl"
      exit 1
    fi
  fi

  step "Installing release ${APIGENE_RELEASE_NAME} into namespace ${APIGENE_NAMESPACE}..."
  # shellcheck disable=SC2086
  helm upgrade --install "${APIGENE_RELEASE_NAME}" "${chart_path}" \
    --namespace "${APIGENE_NAMESPACE}" \
    --create-namespace \
    --set auth.secretKey="${auth_secret}" \
    --wait --timeout 20m \
    ${EXTRA_ARGS}

  ok "Release ${APIGENE_RELEASE_NAME} installed"
}

print_next_steps() {
  section "Next steps"
  info "Watch pods:  kubectl get pods -n ${APIGENE_NAMESPACE} -w"
  info "Port-forward: kubectl port-forward -n ${APIGENE_NAMESPACE} svc/nginx 8080:8080"
  info "Open:        http://localhost:8080"
  info "Test:        cd ${APIGENE_INSTALL_DIR} && ./scripts/run-tests.sh --port-forward"
  info "Uninstall:   helm uninstall ${APIGENE_RELEASE_NAME} -n ${APIGENE_NAMESPACE}"
  echo ""
  echo "✔ Install complete."
}

main() {
  case "${1:-}" in
    -h|--help|help)
      sed -n '2,14p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
  esac

  echo ""
  echo "  Apigene Helm installer"
  echo ""

  section "Prerequisites"
  require_command git "Install Git: https://git-scm.com/downloads" || exit 1
  require_command helm "Install Helm 3: https://helm.sh/docs/intro/install/" || exit 1
  require_command kubectl "Install kubectl: https://kubernetes.io/docs/tasks/tools/" || exit 1
  check_kubectl_cluster || exit 1

  install_repo

  if [[ "${APIGENE_SKIP_INSTALL}" != "1" ]]; then
    run_helm_install
  else
    warn "Skipped helm install (APIGENE_SKIP_INSTALL=1)"
  fi

  print_next_steps
}

main "$@"
