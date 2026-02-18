#!/usr/bin/env bash
set -euo pipefail

# Retry enabling Yellow Flashing (SET_YF) on the controller until utcReplyFR confirms,
# while capturing logs via tools/dk_capture.sh.
#
# Usage:
#   DK_PASS=... tools/yf_retry.sh [--ip 192.168.75.150] [--user voicelink] [--comm UTMC]
#
# Notes:
# - Uses SSH to run snmpget/snmpset on the controller against 127.0.0.1.
# - This changes controller state (ЖМ). Use only when it's safe to do so.

IP="192.168.75.150"
USER="voicelink"
COMM="UTMC"
MAX_ATTEMPTS=20
CONFIRM_SEC=25
SLEEP_AFTER_PHASE_CHANGE=2
HOLD_SEC=60

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ip) IP="$2"; shift 2 ;;
    --user) USER="$2"; shift 2 ;;
    --comm) COMM="$2"; shift 2 ;;
    --max-attempts) MAX_ATTEMPTS="$2"; shift 2 ;;
    --confirm-sec) CONFIRM_SEC="$2"; shift 2 ;;
    --sleep-after-change) SLEEP_AFTER_PHASE_CHANGE="$2"; shift 2 ;;
    --hold-sec) HOLD_SEC="$2"; shift 2 ;;
    -h|--help)
      cat <<EOF
Usage: DK_PASS=... $0 [options]

Options:
  --ip <ip>                 Controller IP (default: $IP)
  --user <user>             SSH user (default: $USER)
  --comm <community>        SNMP community (default: $COMM)
  --max-attempts <n>        Attempts (default: $MAX_ATTEMPTS)
  --confirm-sec <sec>       Confirm window for utcReplyFR after SET_YF (default: $CONFIRM_SEC)
  --sleep-after-change <s>  Delay after phase change before sending SET_YF (default: $SLEEP_AFTER_PHASE_CHANGE)
  --hold-sec <sec>          Hold YF after success (default: $HOLD_SEC)
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

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_DIR="/tmp/dk_yf_retry_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RUN_DIR"

echo "run_dir=$RUN_DIR" | tee "$RUN_DIR/meta_local.txt"
echo "controller=$IP user=$USER comm=$COMM" | tee -a "$RUN_DIR/meta_local.txt"

SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o IdentitiesOnly=yes
  -o PreferredAuthentications=password
  -o PubkeyAuthentication=no
  -o ConnectTimeout=5
)

sshc() {
  # Keep calls short; sshpass shows password briefly in process list.
  sshpass -p "${DK_PASS}" ssh "${SSH_OPTS[@]}" "${USER}@${IP}" "$@"
}

remote_bash() {
  # Execute a bash script body on the controller with vars exported.
  local body="$1"
  sshc "COMM='${COMM}' bash -lc $(printf '%q' "$body")"
}

DK_IP="$IP" DK_USER="$USER" DK_PASS="$DK_PASS" "$ROOT_DIR/tools/dk_capture.sh" start "$RUN_DIR" | tee "$RUN_DIR/capture_start.txt"

# OIDs (used on controller against 127.0.0.1)
OID_MODE="1.3.6.1.4.1.13267.3.2.4.1"
OID_LO="1.3.6.1.4.1.13267.3.2.4.2.1.11"
OID_FF="1.3.6.1.4.1.13267.3.2.4.2.1.20"
OID_GN="1.3.6.1.4.1.13267.3.2.5.1.1.3"
OID_FR="1.3.6.1.4.1.13267.3.2.5.1.1.36"

remote_bash "
set -euo pipefail
which snmpget >/dev/null
which snmpset >/dev/null
snmpget -v1 -c \"\$COMM\" -t 1 -r 0 -Oqv 127.0.0.1 $OID_MODE >/dev/null
echo ok
"

remote_bash "
set -euo pipefail
snmpset -v1 -c \"\$COMM\" -Oqv 127.0.0.1 $OID_LO i 0 $OID_FF i 0 $OID_MODE i 1 >/dev/null
echo restored_normal
snmpget -v1 -c \"\$COMM\" -Oqv 127.0.0.1 $OID_MODE $OID_FR $OID_GN
" | tee -a "$RUN_DIR/attempts.log"

success=0
for i in $(seq 1 "$MAX_ATTEMPTS"); do
  echo "attempt=$i ts=$(date -Iseconds)" | tee -a "$RUN_DIR/attempts.log"

  # Always start each attempt from Standalone.
  remote_bash "
set -euo pipefail
snmpset -v1 -c \"\$COMM\" -Oqv 127.0.0.1 $OID_LO i 0 $OID_FF i 0 $OID_MODE i 1 >/dev/null
"

  # Wait for phase to change, then delay a bit to avoid boundary/transition tick.
  remote_bash "
set -euo pipefail
prev=\$(snmpget -v1 -c \"\$COMM\" -t 1 -r 0 -Oqv 127.0.0.1 $OID_GN 2>/dev/null || echo '?')
start=\$(date +%s)
while :; do
  cur=\$(snmpget -v1 -c \"\$COMM\" -t 1 -r 0 -Oqv 127.0.0.1 $OID_GN 2>/dev/null || echo '?')
  if [ \"\$cur\" != \"\$prev\" ] && [ \"\$cur\" != '?' ]; then
    echo \"phase_change: \$prev -> \$cur\"
    break
  fi
  now=\$(date +%s)
  if [ \$((now-start)) -ge 40 ]; then
    echo \"phase_change: timeout (prev=\$prev cur=\$cur)\"
    break
  fi
  sleep 0.2
done
sleep $SLEEP_AFTER_PHASE_CHANGE
echo \"pre_send: mode=\$(snmpget -v1 -c \\\"\\\$COMM\\\" -Oqv 127.0.0.1 $OID_MODE 2>/dev/null || echo ?) fr=\$(snmpget -v1 -c \\\"\\\$COMM\\\" -Oqv 127.0.0.1 $OID_FR 2>/dev/null || echo ?) gn=\$(snmpget -v1 -c \\\"\\\$COMM\\\" -Oqv 127.0.0.1 $OID_GN 2>/dev/null || echo ?)\" 
" | tee -a "$RUN_DIR/attempts.log"

  # Send SET_YF (single transaction).
  remote_bash "
set -euo pipefail
snmpset -v1 -c \"\$COMM\" -Oqv 127.0.0.1 $OID_MODE i 3 $OID_FF i 1 >/dev/null
echo sent_set_yf
" | tee -a "$RUN_DIR/attempts.log"

  # Confirm FR.
  out="$(remote_bash "
set -euo pipefail
start=\$(date +%s)
while :; do
  fr=\$(snmpget -v1 -c \"\$COMM\" -t 1 -r 0 -Oqv 127.0.0.1 $OID_FR 2>/dev/null || echo '?')
  if [ \"\$fr\" != '?' ] && [ \"\$fr\" != '0' ]; then
    echo \"confirmed_fr=\$fr\"
    exit 0
  fi
  now=\$(date +%s)
  if [ \$((now-start)) -ge $CONFIRM_SEC ]; then
    echo \"confirm_timeout fr=\$fr\"
    exit 0
  fi
  sleep 0.2
done
")"
  echo "$out" | tee -a "$RUN_DIR/attempts.log"

  if echo "$out" | rg -q '^confirmed_fr='; then
    success=1
    echo "SUCCESS attempt=$i" | tee -a "$RUN_DIR/attempts.log"
    break
  fi

  # Cleanup to normal before next attempt.
  remote_bash "
set -euo pipefail
snmpset -v1 -c \"\$COMM\" -Oqv 127.0.0.1 $OID_FF i 0 $OID_LO i 0 $OID_MODE i 1 >/dev/null
echo cleaned_to_normal
" | tee -a "$RUN_DIR/attempts.log"
  sleep 3
done

echo "success=$success" | tee -a "$RUN_DIR/attempts.log"

if [[ "$success" == "1" ]]; then
  remote_bash "
set -euo pipefail
echo holding_yf_${HOLD_SEC}s
sleep $HOLD_SEC
snmpget -v1 -c \"\$COMM\" -Oqv 127.0.0.1 $OID_FR $OID_MODE $OID_GN || true
" | tee -a "$RUN_DIR/attempts.log" || true

  remote_bash "
set -euo pipefail
snmpset -v1 -c \"\$COMM\" -Oqv 127.0.0.1 $OID_FF i 0 $OID_LO i 0 $OID_MODE i 1 >/dev/null
echo restored_final
snmpget -v1 -c \"\$COMM\" -Oqv 127.0.0.1 $OID_FR $OID_MODE || true
" | tee -a "$RUN_DIR/attempts.log" || true
fi

DK_IP="$IP" DK_USER="$USER" DK_PASS="$DK_PASS" "$ROOT_DIR/tools/dk_capture.sh" stop | tee "$RUN_DIR/capture_stop.txt" || true
DK_IP="$IP" DK_USER="$USER" DK_PASS="$DK_PASS" "$ROOT_DIR/tools/dk_capture.sh" pull "$RUN_DIR" | tee "$RUN_DIR/capture_pull.txt" || true

if [[ -f "$RUN_DIR/capture.tgz" ]]; then
  tar -xzf "$RUN_DIR/capture.tgz" -C "$RUN_DIR" || true
fi

BASE="$(find "$RUN_DIR" -type d -name 'dk_capture_*' | head -n 1 || true)"
{
  echo "base=$BASE"
  echo "success=$success"
  if [[ -n "$BASE" ]]; then
    rg -n "SET_YF" "$BASE/spectr_utmc_follow.log" | tail -n 30 || true
    rg -n "Flashing yellow" "$BASE/resident_follow.log" | tail -n 30 || true
    rg -n "\\bfr=1\\b" "$BASE/snmp_poll.log" | head -n 50 || true
  fi
} >"$RUN_DIR/summary.txt"

DST="$ROOT_DIR/spectr_utmc/controller_snapshot/experiments/$(date +%Y-%m-%d_%H%M%S)_yf_retry"
mkdir -p "$DST"
cp -a "$RUN_DIR/"* "$DST/" || true
echo "dst=$DST" >>"$RUN_DIR/summary.txt"
echo "$DST"

