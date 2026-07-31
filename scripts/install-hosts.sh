#!/bin/bash
# One-time local DNS + port 80 setup for http://demo.io/bi (needs sudo).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
[[ -f "$ROOT/.env" ]] && set -a && source "$ROOT/.env" && set +a

BI_HOSTNAME="${BI_HOSTNAME:-demo.io}"
MARKER="# superset-bi-demo-hosts"
SYSCTL_FILE="/etc/sysctl.d/99-superset-bi-demo.conf"

echo "== /etc/hosts (${BI_HOSTNAME} → loopback) =="
if grep -qF "$MARKER" /etc/hosts 2>/dev/null; then
  sudo sed -i "/${MARKER}/d" /etc/hosts
fi
printf '%s\n' \
  "127.0.0.1 ${BI_HOSTNAME} ${MARKER}" \
  "::1 ${BI_HOSTNAME} ${MARKER}" \
  | sudo tee -a /etc/hosts >/dev/null
grep -F "$MARKER" /etc/hosts

echo
echo "== allow rootless bind on port 80 =="
# Default on many systems is 1024; gateway needs :80 for portless URLs.
echo "net.ipv4.ip_unprivileged_port_start=80" | sudo tee "$SYSCTL_FILE" >/dev/null
sudo sysctl -p "$SYSCTL_FILE"

echo
echo "Ready:"
echo "  App:  http://${BI_HOSTNAME}/bi/"
echo "  Auth: http://${BI_HOSTNAME}/auth/"
echo "Then: make up && make verify"
