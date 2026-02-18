#!/usr/bin/env bash
set -euo pipefail

# Read-only connectivity diagnostics for the SINTEZ controller.
# Usage:
#   DK_PASS=... tools/connectivity_check.sh [--ip 192.168.75.150] [--user voicelink] [--comm UTMC]

IP="192.168.75.150"
USER="voicelink"
COMM="UTMC"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ip) IP="$2"; shift 2 ;;
    --user) USER="$2"; shift 2 ;;
    --comm) COMM="$2"; shift 2 ;;
    -h|--help)
      cat <<EOF
Usage: DK_PASS=... $0 [options]

Options:
  --ip <ip>          Controller IP (default: $IP)
  --user <user>      SSH user (default: $USER)
  --comm <community> SNMP community (default: $COMM)
EOF
      exit 0
      ;;
    *)
      echo "error: unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

[[ -n "${DK_PASS:-}" ]] || { echo "error: DK_PASS is required" >&2; exit 2; }

RUN_DIR="/tmp/dk_connectivity_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RUN_DIR"
OUT="$RUN_DIR/connectivity.txt"

SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o IdentitiesOnly=yes
  -o PreferredAuthentications=password
  -o PubkeyAuthentication=no
  -o ConnectTimeout=5
)

sshc() {
  sshpass -p "${DK_PASS}" ssh "${SSH_OPTS[@]}" "${USER}@${IP}" "$@"
}

remote_bash() {
  local body="$1"
  sshc "COMM='${COMM}' bash -lc $(printf '%q' "$body")"
}

{
  echo "local_time=$(date -Iseconds)"
  echo "ip=$IP user=$USER comm=$COMM"
  echo
  echo "== ping =="
  ping -c 2 -W 1 "$IP" || true
  echo
  echo "== ssh echo =="
  sshc "echo ok" || true
  echo
  echo "== controller sys =="
remote_bash "
set -e
echo \"controller_time=\$(date -Iseconds)\"
(uptime -p 2>/dev/null || uptime) || true
uname -a || true
echo
echo \"== net ==\"
ip -brief addr show eth0 || true
ip route || true
echo
echo \"== spectr_utmc ==\"
systemctl is-active spectr_utmc 2>/dev/null || true
systemctl status spectr_utmc --no-pager -l | head -n 40 || true
echo
echo \"== snmpget (local 127.0.0.1) ==\"
which snmpget || true
which snmpset || true
printf 'operationMode='; snmpget -v1 -c \"\$COMM\" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.1 2>&1 || true
printf 'utcReplyFR=';    snmpget -v1 -c \"\$COMM\" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.5.1.1.36 2>&1 || true
printf 'utcReplyGn=';    snmpget -v1 -c \"\$COMM\" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.5.1.1.3 2>&1 || true
printf 'utcControlLO=';  snmpget -v1 -c \"\$COMM\" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.11 2>&1 || true
printf 'utcControlFF=';  snmpget -v1 -c \"\$COMM\" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 2>&1 || true
echo
echo \"== timing OIDs (may be unsupported) ==\"
snmpget -v1 -c \"\$COMM\" -t 1 -r 0 127.0.0.1 1.3.6.1.4.1.13267.3.2.5.1.1.4 2>&1 || true
snmpget -v1 -c \"\$COMM\" -t 1 -r 0 127.0.0.1 1.3.6.1.4.1.13267.3.2.5.1.1.5 2>&1 || true
snmpget -v1 -c \"\$COMM\" -t 1 -r 0 127.0.0.1 1.3.6.1.4.1.13267.3.2.5.1.1.7 2>&1 || true
" || true
} | tee "$OUT"

echo "$RUN_DIR"
