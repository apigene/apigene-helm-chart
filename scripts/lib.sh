#!/usr/bin/env bash
# Shared helpers for apigene-helm-chart scripts.

show_deploy_progress() {
  local ns="${1:?namespace required}"
  echo ""
  echo "--- $(date -u +%H:%M:%S) deploy progress (${ns}) ---"
  if kubectl get namespace "${ns}" >/dev/null 2>&1; then
    kubectl get pods -n "${ns}" --no-headers 2>/dev/null || true
  else
    echo "  (namespace not created yet)"
  fi
  echo "-------------------------------------------"
}

watch_deploy_progress() {
  local ns="${1:?namespace required}"
  local interval="${2:-30}"
  show_deploy_progress "${ns}"
  while true; do
    sleep "${interval}"
    show_deploy_progress "${ns}"
  done
}

stop_deploy_progress() {
  local pid="${1:-}"
  [[ -n "${pid}" ]] || return 0
  kill "${pid}" 2>/dev/null || true
  wait "${pid}" 2>/dev/null || true
}
