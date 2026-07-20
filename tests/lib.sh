#!/usr/bin/env bash
# Minimal test output helpers for apigene-helm-chart (no docker-compose CLI deps).

tests_init_colors() {
  if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_RESET='\033[0m'
    C_BOLD='\033[1m'
    C_DIM='\033[2m'
    C_RED='\033[0;31m'
    C_GREEN='\033[0;32m'
    C_YELLOW='\033[0;33m'
    C_CYAN='\033[0;36m'
    C_MAGENTA='\033[0;35m'
  else
    C_RESET='' C_BOLD='' C_DIM='' C_RED='' C_GREEN='' C_YELLOW=''
    C_CYAN='' C_MAGENTA=''
  fi
}

apigene_banner() {
  local title="$1"
  echo -e "${C_BOLD}${C_MAGENTA}"
  echo "  ╔══════════════════════════════════════╗"
  printf "  ║ %-36s ║\n" "$title"
  echo "  ╚══════════════════════════════════════╝"
  echo -e "${C_RESET}"
}

apigene_section() {
  echo ""
  echo -e "${C_BOLD}${C_CYAN}━━ $1 ━━${C_RESET}"
}

apigene_info() {
  echo -e "  ${C_DIM}·${C_RESET}  $1"
}

apigene_ok() {
  echo -e "  ${C_GREEN}✔${C_RESET}  $1"
}

apigene_warn() {
  echo -e "  ${C_YELLOW}!${C_RESET}  $1"
}

apigene_err() {
  echo -e "  ${C_RED}✘${C_RESET}  $1" >&2
}
