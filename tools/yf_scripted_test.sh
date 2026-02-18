#!/usr/bin/env bash
set -euo pipefail

# Scripted Yellow Flashing (ЖМ) scenario using controller-local SNMP via SSH.
# It captures logs via tools/dk_capture.sh and writes an MD report.
#
# Scenario:
#  1) Enable YF for 60s
#  2) Restore normal
#  3) Wait 120s
#  4) Enable YF for 60s
#  5) Restore normal
#
# Usage:
#   DK_PASS=... tools/yf_scripted_test.sh [--ip 192.168.75.150] [--user voicelink] [--comm UTMC]

IP="192.168.75.150"
USER="voicelink"
COMM="UTMC"

YF_ENABLE_TIMEOUT_SEC=120
YF_SET_PERIOD_SEC=2
YF_HOLD_SEC=60
BETWEEN_SEC=120

CONFIRM_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ip) IP="$2"; shift 2 ;;
    --user) USER="$2"; shift 2 ;;
    --comm) COMM="$2"; shift 2 ;;
    --yf-enable-timeout) YF_ENABLE_TIMEOUT_SEC="$2"; shift 2 ;;
    --yf-set-period) YF_SET_PERIOD_SEC="$2"; shift 2 ;;
    --yf-hold) YF_HOLD_SEC="$2"; shift 2 ;;
    --between) BETWEEN_SEC="$2"; shift 2 ;;
    --confirm) CONFIRM_RUN=1; shift 1 ;;
    -h|--help)
      cat <<EOF
Usage: DK_PASS=... $0 [options]

Options:
  --ip <ip>                 (default: $IP)
  --user <user>             (default: $USER)
  --comm <community>        (default: $COMM)
  --yf-enable-timeout <sec> (default: $YF_ENABLE_TIMEOUT_SEC)
  --yf-set-period <sec>     (default: $YF_SET_PERIOD_SEC)
  --yf-hold <sec>           (default: $YF_HOLD_SEC)
  --between <sec>           (default: $BETWEEN_SEC)
  --confirm                 Required. Without this flag the script will only print the planned scenario and exit.
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
RUN_DIR="/tmp/yf_scripted_test_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RUN_DIR"

SCENARIO_LOG="$RUN_DIR/scenario.log"
CMD_LOG="$RUN_DIR/commands.log"

echo "run_dir=$RUN_DIR" >"$RUN_DIR/meta_local.txt"
{
  echo "controller_ip=$IP"
  echo "ssh_user=$USER"
  echo "community=$COMM"
  echo "yf_enable_timeout_sec=$YF_ENABLE_TIMEOUT_SEC"
  echo "yf_set_period_sec=$YF_SET_PERIOD_SEC"
  echo "yf_hold_sec=$YF_HOLD_SEC"
  echo "between_sec=$BETWEEN_SEC"
} >>"$RUN_DIR/meta_local.txt"

if [[ "$CONFIRM_RUN" != "1" ]]; then
  cat <<EOF
Planned scenario (dry run; no controller commands executed):
1) Enable YF (ЖМ) and confirm by utcReplyFR (timeout: ${YF_ENABLE_TIMEOUT_SEC}s)
2) Hold YF for ${YF_HOLD_SEC}s (keep asserting SetAF=1 every ${YF_SET_PERIOD_SEC}s)
3) Restore normal (mode=1, FF=0, LO=0)
4) Wait ${BETWEEN_SEC}s
5) Enable YF again + hold ${YF_HOLD_SEC}s
6) Restore normal

To actually run: add --confirm
Output dir would be: ${RUN_DIR}
EOF
  exit 0
fi

SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
  -o IdentitiesOnly=yes
  -o PreferredAuthentications=password
  -o PubkeyAuthentication=no
  -o ConnectTimeout=5
)

sshc() {
  sshpass -p "${DK_PASS}" ssh "${SSH_OPTS[@]}" "${USER}@${IP}" "$@"
}

remote() {
  local body="$1"
  echo "[$(date -Iseconds)] ssh bash -lc: $body" >>"$CMD_LOG"
  sshc "COMM='${COMM}' bash -lc $(printf '%q' "$body")"
}

log() {
  echo "[$(date -Iseconds)] $*" | tee -a "$SCENARIO_LOG"
}

# OIDs
OID_MODE="1.3.6.1.4.1.13267.3.2.4.1"
OID_LO="1.3.6.1.4.1.13267.3.2.4.2.1.11"
OID_FF="1.3.6.1.4.1.13267.3.2.4.2.1.20"
OID_FR="1.3.6.1.4.1.13267.3.2.5.1.1.36"
OID_GN="1.3.6.1.4.1.13267.3.2.5.1.1.3"

restore_normal() {
  remote "set -euo pipefail
snmpset -v1 -c \"\$COMM\" -t 2 -r 1 -Oqv 127.0.0.1 \
  $OID_LO i 0 \
  $OID_FF i 0 \
  $OID_MODE i 1 >/dev/null
sleep 1
echo mode=\$(snmpget -v1 -c \"\$COMM\" -t 2 -r 1 -Oqv 127.0.0.1 $OID_MODE 2>/dev/null || echo '?') \
     fr=\$(snmpget -v1 -c \"\$COMM\" -t 2 -r 1 -Oqv 127.0.0.1 $OID_FR 2>/dev/null || echo '?')"
}

enable_yf_until_confirm() {
  # Enter UTC control once, then repeatedly assert FF=1 until FR==1 or timeout.
  local start_s now_s
  start_s="$(date +%s)"
  remote "set -euo pipefail; snmpset -v1 -c \"\$COMM\" -t 2 -r 1 -Oqv 127.0.0.1 $OID_MODE i 3 >/dev/null; echo mode_set_3"

  while :; do
    remote "set -euo pipefail; snmpset -v1 -c \"\$COMM\" -t 2 -r 1 -Oqv 127.0.0.1 $OID_FF i 1 >/dev/null; echo ff_set_1"
    local fr
    fr="$(remote "set -euo pipefail; snmpget -v1 -c \"\$COMM\" -t 2 -r 1 -Oqv 127.0.0.1 $OID_FR 2>/dev/null || echo '?'")"
    echo "[$(date -Iseconds)] fr=$fr" >>"$SCENARIO_LOG"
    if [[ "$fr" != "0" && "$fr" != "?" ]]; then
      log "CONFIRMED: utcReplyFR=$fr"
      return 0
    fi
    now_s="$(date +%s)"
    if [[ $((now_s - start_s)) -ge "$YF_ENABLE_TIMEOUT_SEC" ]]; then
      log "ERROR: enable_yf timeout (no utcReplyFR confirmation)"
      return 1
    fi
    sleep "$YF_SET_PERIOD_SEC"
  done
}

cleanup() {
  set +e
  log "CLEANUP: restore normal + stop capture (best-effort)"
  restore_normal >/dev/null 2>&1 || true
  DK_IP="$IP" DK_USER="$USER" DK_PASS="$DK_PASS" "$ROOT_DIR/tools/dk_capture.sh" stop >/dev/null 2>&1 || true
  DK_IP="$IP" DK_USER="$USER" DK_PASS="$DK_PASS" "$ROOT_DIR/tools/dk_capture.sh" pull "$RUN_DIR" >/dev/null 2>&1 || true
}
trap cleanup INT TERM

log "START capture"
DK_IP="$IP" DK_USER="$USER" DK_PASS="$DK_PASS" "$ROOT_DIR/tools/dk_capture.sh" start "$RUN_DIR" >>"$SCENARIO_LOG" 2>&1

log "Baseline: mode/fr/gn"
remote "set -euo pipefail; echo mode=\$(snmpget -v1 -c \"\$COMM\" -t 2 -r 1 -Oqv 127.0.0.1 $OID_MODE); echo fr=\$(snmpget -v1 -c \"\$COMM\" -t 2 -r 1 -Oqv 127.0.0.1 $OID_FR); echo gn=\$(snmpget -v1 -c \"\$COMM\" -t 2 -r 1 -Oqv 127.0.0.1 $OID_GN)" >>"$SCENARIO_LOG" 2>&1 || true

log "STEP 1: enable YF"
enable_yf_until_confirm
log "STEP 1: hold YF ${YF_HOLD_SEC}s (keep asserting FF=1)"
hold_start="$(date +%s)"
while [[ $(( $(date +%s) - hold_start )) -lt "$YF_HOLD_SEC" ]]; do
  remote "set -euo pipefail; snmpset -v1 -c \"\$COMM\" -t 2 -r 1 -Oqv 127.0.0.1 $OID_FF i 1 >/dev/null; echo ff_keep_1" >>"$SCENARIO_LOG" 2>&1 || true
  sleep "$YF_SET_PERIOD_SEC"
done

log "STEP 2: restore normal"
restore_normal >>"$SCENARIO_LOG" 2>&1 || true

log "STEP 3: wait ${BETWEEN_SEC}s"
sleep "$BETWEEN_SEC"

log "STEP 4: enable YF again"
enable_yf_until_confirm
log "STEP 4: hold YF ${YF_HOLD_SEC}s (keep asserting FF=1)"
hold_start="$(date +%s)"
while [[ $(( $(date +%s) - hold_start )) -lt "$YF_HOLD_SEC" ]]; do
  remote "set -euo pipefail; snmpset -v1 -c \"\$COMM\" -t 2 -r 1 -Oqv 127.0.0.1 $OID_FF i 1 >/dev/null; echo ff_keep_1" >>"$SCENARIO_LOG" 2>&1 || true
  sleep "$YF_SET_PERIOD_SEC"
done

log "STEP 5: restore normal"
restore_normal >>"$SCENARIO_LOG" 2>&1 || true

log "STOP capture + pull"
DK_IP="$IP" DK_USER="$USER" DK_PASS="$DK_PASS" "$ROOT_DIR/tools/dk_capture.sh" stop >>"$SCENARIO_LOG" 2>&1 || true
DK_IP="$IP" DK_USER="$USER" DK_PASS="$DK_PASS" "$ROOT_DIR/tools/dk_capture.sh" pull "$RUN_DIR" >>"$SCENARIO_LOG" 2>&1 || true

mkdir -p "$RUN_DIR/extracted"
tar -xzf "$RUN_DIR/capture.tgz" -C "$RUN_DIR/extracted" || true
BASE="$(find "$RUN_DIR/extracted" -type d -name 'dk_capture_*' | head -n 1 || true)"
echo "base=$BASE" >"$RUN_DIR/base.txt"

REPORT="$RUN_DIR/report.md"
"$ROOT_DIR/tools/yf_make_report.py" --run-dir "$RUN_DIR" --base-dir "$BASE" --out "$REPORT" || true

DST="$ROOT_DIR/spectr_utmc/controller_snapshot/experiments/$(date +%Y-%m-%d_%H%M%S)_yf_scripted_test"
mkdir -p "$DST"
cp -a "$RUN_DIR/"* "$DST/" || true
echo "$DST"
