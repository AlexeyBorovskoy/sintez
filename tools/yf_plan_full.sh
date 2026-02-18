#!/usr/bin/env bash
set -euo pipefail

# Full test plan run:
#  1) Enable Yellow Flashing (ЖМ) and confirm by utcReplyFR (retry loop).
#  2) Hold ЖМ for hold1 seconds.
#  3) Restore normal (LO=0, FF=0, mode=1), observe normal program for observe1 seconds.
#  4) Enable ЖМ again (retry loop), hold for hold2 seconds.
#  5) Restore normal again, observe for observe2 seconds.
#
# Captures controller logs via tools/dk_capture.sh and saves everything under
# spectr_utmc/controller_snapshot/experiments/<timestamp>_yf_plan_full
#
# Usage:
#   DK_PASS=... tools/yf_plan_full.sh [--ip ...] [--user ...] [--comm UTMC]

IP="192.168.75.150"
USER="voicelink"
COMM="UTMC"

MAX_ATTEMPTS=30
CONFIRM_SEC=25
SLEEP_AFTER_PHASE_CHANGE=2

# Core YF strategy: keep SetAF (utcControlFF=1) asserted for >=10s (per protocol.txt)
# by periodically resending it for a window until utcReplyFR confirms.
YF_SEND_PERIOD_SEC=2
YF_WINDOW_SEC=90
YF_MIN_ASSERT_SEC=12

HOLD1_SEC=45
OBSERVE1_SEC=600   # 10 minutes (2-3 cycles can be ~7-11 minutes on this DK)
HOLD2_SEC=60
OBSERVE2_SEC=120

PHASE_FALLBACK=1   # if direct attempts fail: try setting nominated phase to 0x01 before SET_YF

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ip) IP="$2"; shift 2 ;;
    --user) USER="$2"; shift 2 ;;
    --comm) COMM="$2"; shift 2 ;;
    --max-attempts) MAX_ATTEMPTS="$2"; shift 2 ;;
    --confirm-sec) CONFIRM_SEC="$2"; shift 2 ;;
    --sleep-after-change) SLEEP_AFTER_PHASE_CHANGE="$2"; shift 2 ;;
    --hold1-sec) HOLD1_SEC="$2"; shift 2 ;;
    --observe1-sec) OBSERVE1_SEC="$2"; shift 2 ;;
    --hold2-sec) HOLD2_SEC="$2"; shift 2 ;;
    --observe2-sec) OBSERVE2_SEC="$2"; shift 2 ;;
    --phase-fallback) PHASE_FALLBACK="$2"; shift 2 ;;
    -h|--help)
      cat <<EOF
Usage: DK_PASS=... $0 [options]

Options:
  --ip <ip>                 Controller IP (default: $IP)
  --user <user>             SSH user (default: $USER)
  --comm <community>        SNMP community (default: $COMM)
  --max-attempts <n>        Attempts per YF enable stage (default: $MAX_ATTEMPTS)
  --confirm-sec <sec>       Confirm window for utcReplyFR (default: $CONFIRM_SEC)
  --sleep-after-change <s>  Delay after phase change before sending SET_YF (default: $SLEEP_AFTER_PHASE_CHANGE)
  --hold1-sec <sec>         Hold first YF (default: $HOLD1_SEC)
  --observe1-sec <sec>      Observe normal after first restore (default: $OBSERVE1_SEC)
  --hold2-sec <sec>         Hold second YF (default: $HOLD2_SEC)
  --observe2-sec <sec>      Observe normal after second restore (default: $OBSERVE2_SEC)
  --phase-fallback <0|1>    Enable phase-set fallback before SET_YF (default: $PHASE_FALLBACK)
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
RUN_DIR="/tmp/dk_yf_plan_full_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RUN_DIR"

echo "run_dir=$RUN_DIR" | tee "$RUN_DIR/meta_local.txt"
echo "controller=$IP user=$USER comm=$COMM" | tee -a "$RUN_DIR/meta_local.txt"

CAPTURE_STARTED=0

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

remote_bash() {
  local body="$1"
  sshc "COMM='${COMM}' bash -lc $(printf '%q' "$body")"
}

log() {
  printf '[%s] %s\n' "$(date -Iseconds)" "$*" | tee -a "$RUN_DIR/run.log"
}

# Best-effort cleanup even if we Ctrl+C.
cleanup() {
  set +e
  set +u
  log "CLEANUP: restoring controller to normal (LO=0, FF=0, mode=1)"
  sshc "snmpset -v1 -c ${COMM} -t 2 -r 1 -Oqv 127.0.0.1 \
    ${OID_LO} i 0 ${OID_FF} i 0 ${OID_MODE} i 1 >/dev/null 2>&1" || true
  if [[ "$CAPTURE_STARTED" == "1" ]]; then
    log "CLEANUP: stopping capture"
    DK_IP="$IP" DK_USER="$USER" DK_PASS="$DK_PASS" "$ROOT_DIR/tools/dk_capture.sh" stop >/dev/null 2>&1 || true
    DK_IP="$IP" DK_USER="$USER" DK_PASS="$DK_PASS" "$ROOT_DIR/tools/dk_capture.sh" pull "$RUN_DIR" >/dev/null 2>&1 || true
  fi
}
trap cleanup INT TERM

# OIDs (controller local 127.0.0.1)
OID_MODE="1.3.6.1.4.1.13267.3.2.4.1"
OID_LO="1.3.6.1.4.1.13267.3.2.4.2.1.11"
OID_FF="1.3.6.1.4.1.13267.3.2.4.2.1.20"
OID_FN="1.3.6.1.4.1.13267.3.2.4.2.1.5"
OID_GN="1.3.6.1.4.1.13267.3.2.5.1.1.3"
OID_FR="1.3.6.1.4.1.13267.3.2.5.1.1.36"

restore_normal() {
  remote_bash "
set -euo pipefail
snmpset -v1 -c \"\$COMM\" -t 2 -r 1 -Oqv 127.0.0.1 $OID_LO i 0 $OID_FF i 0 $OID_MODE i 1 >/dev/null
sleep 1
echo restored_normal mode=\$(snmpget -v1 -c \"\$COMM\" -t 2 -r 1 -Oqv 127.0.0.1 $OID_MODE 2>/dev/null || echo ?) fr=\$(snmpget -v1 -c \"\$COMM\" -t 2 -r 1 -Oqv 127.0.0.1 $OID_FR 2>/dev/null || echo ?)
"
}

wait_phase_change_and_delay() {
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
"
}

send_set_yf_direct() {
  remote_bash "
set -euo pipefail
snmpset -v1 -c \"\$COMM\" -t 2 -r 1 -Oqv 127.0.0.1 $OID_FF i 1 >/dev/null
echo set_ff_1
"
}

enter_utc_control() {
  remote_bash "
set -euo pipefail
snmpset -v1 -c \"\$COMM\" -t 2 -r 1 -Oqv 127.0.0.1 $OID_MODE i 3 >/dev/null
echo set_mode_3
"
}

send_set_phase_fallback() {
  remote_bash "
set -euo pipefail
# Set nominated phase (0x01) in UTC control mode, then attempt YF.
snmpset -v1 -c \"\$COMM\" -t 2 -r 1 -Oqv 127.0.0.1 $OID_MODE i 3 $OID_FN x 01 >/dev/null
echo set_phase_fallback_done
"
}

confirm_fr() {
  remote_bash "
set -euo pipefail
fr=\$(snmpget -v1 -c \"\$COMM\" -t 2 -r 1 -Oqv 127.0.0.1 $OID_FR 2>/dev/null || echo '?')
echo \"fr=\$fr\"
"
}

enable_yf_with_retry() {
  local label="$1"
  log "Enable YF stage: $label (window=${YF_WINDOW_SEC}s period=${YF_SEND_PERIOD_SEC}s)"
  restore_normal | tee -a "$RUN_DIR/run.log"

  local attempt=1
  local success=0

  while [[ "$attempt" -le "$MAX_ATTEMPTS" ]]; do
    log "$label: burst $attempt/$MAX_ATTEMPTS"

    enter_utc_control | tee -a "$RUN_DIR/run.log"

    # Optional: nudge nominated phase once early in the run.
    if [[ "$PHASE_FALLBACK" == "1" && "$attempt" -eq 2 ]]; then
      log "$label: set nominated phase (fallback)"
      send_set_phase_fallback | tee -a "$RUN_DIR/run.log" || true
    fi

    local start_ts
    start_ts="$(date +%s)"
    local first_assert_ts
    first_assert_ts=""
    while :; do
      send_set_yf_direct | tee -a "$RUN_DIR/run.log"

      if [[ -z "$first_assert_ts" ]]; then
        first_assert_ts="$(date +%s)"
      fi

      # Only start treating FR!=0 as definitive after we've asserted FF=1 long enough.
      now_ts="$(date +%s)"
      if [[ $((now_ts - first_assert_ts)) -ge "$YF_MIN_ASSERT_SEC" ]]; then
        local fr_line
        fr_line="$(confirm_fr)"
        echo "$fr_line" | tee -a "$RUN_DIR/run.log"
        if echo "$fr_line" | rg -q '^fr='; then
          fr_val="$(echo "$fr_line" | sed 's/^fr=//')"
          if [[ "$fr_val" != "0" && "$fr_val" != "?" ]]; then
            success=1
            log "$label: SUCCESS confirmed_fr=$fr_val"
            break
          fi
        fi
      fi

      if [[ $((now_ts - start_ts)) -ge "$YF_WINDOW_SEC" ]]; then
        log "$label: window expired (no confirm)"
        break
      fi
      sleep "$YF_SEND_PERIOD_SEC"
    done

    if [[ "$success" == "1" ]]; then
      break
    fi

    # cleanup between bursts
    restore_normal | tee -a "$RUN_DIR/run.log" || true
    sleep 2
    attempt=$((attempt + 1))
  done

  echo "$success"
}

log "Starting dk_capture..."
DK_IP="$IP" DK_USER="$USER" DK_PASS="$DK_PASS" "$ROOT_DIR/tools/dk_capture.sh" start "$RUN_DIR" | tee "$RUN_DIR/capture_start.txt"
CAPTURE_STARTED=1

log "STEP 0: sanity read (mode/fr/gn)"
remote_bash "
set -euo pipefail
echo mode=\$(snmpget -v1 -c \"\$COMM\" -Oqv 127.0.0.1 $OID_MODE)
echo fr=\$(snmpget -v1 -c \"\$COMM\" -Oqv 127.0.0.1 $OID_FR)
echo gn=\$(snmpget -v1 -c \"\$COMM\" -Oqv 127.0.0.1 $OID_GN)
" | tee -a "$RUN_DIR/run.log"

log "STEP 1: enable YF and hold ${HOLD1_SEC}s"
ok1="$(enable_yf_with_retry "YF1")"
echo "YF1_success=$ok1" | tee -a "$RUN_DIR/run.log"
if [[ "$ok1" != "1" ]]; then
  log "YF1 failed: stopping capture and saving artifacts"
  DK_IP="$IP" DK_USER="$USER" DK_PASS="$DK_PASS" "$ROOT_DIR/tools/dk_capture.sh" stop | tee "$RUN_DIR/capture_stop.txt" || true
  DK_IP="$IP" DK_USER="$USER" DK_PASS="$DK_PASS" "$ROOT_DIR/tools/dk_capture.sh" pull "$RUN_DIR" | tee "$RUN_DIR/capture_pull.txt" || true
  exit 3
fi

remote_bash "set -euo pipefail; echo holding_yf_${HOLD1_SEC}s; sleep $HOLD1_SEC; snmpget -v1 -c \"\$COMM\" -Oqv 127.0.0.1 $OID_FR $OID_MODE $OID_GN || true" | tee -a "$RUN_DIR/run.log" || true

log "STEP 2: restore normal and observe ${OBSERVE1_SEC}s"
restore_normal | tee -a "$RUN_DIR/run.log"
log "Observing normal..."
sleep "$OBSERVE1_SEC"

log "STEP 3: enable YF again and hold ${HOLD2_SEC}s"
ok2="$(enable_yf_with_retry "YF2")"
echo "YF2_success=$ok2" | tee -a "$RUN_DIR/run.log"
if [[ "$ok2" != "1" ]]; then
  log "YF2 failed (continuing to cleanup)"
fi
remote_bash "set -euo pipefail; echo holding_yf_${HOLD2_SEC}s; sleep $HOLD2_SEC; snmpget -v1 -c \"\$COMM\" -Oqv 127.0.0.1 $OID_FR $OID_MODE $OID_GN || true" | tee -a "$RUN_DIR/run.log" || true

log "STEP 4: restore normal again and observe ${OBSERVE2_SEC}s"
restore_normal | tee -a "$RUN_DIR/run.log"
sleep "$OBSERVE2_SEC"

log "Stopping capture + pulling artifacts..."
DK_IP="$IP" DK_USER="$USER" DK_PASS="$DK_PASS" "$ROOT_DIR/tools/dk_capture.sh" stop | tee "$RUN_DIR/capture_stop.txt" || true
DK_IP="$IP" DK_USER="$USER" DK_PASS="$DK_PASS" "$ROOT_DIR/tools/dk_capture.sh" pull "$RUN_DIR" | tee "$RUN_DIR/capture_pull.txt" || true
CAPTURE_STARTED=0

if [[ -f "$RUN_DIR/capture.tgz" ]]; then
  tar -xzf "$RUN_DIR/capture.tgz" -C "$RUN_DIR" || true
fi

BASE="$(find "$RUN_DIR" -type d -name 'dk_capture_*' | head -n 1 || true)"
echo "base=$BASE" | tee "$RUN_DIR/summary.txt"

python3 - <<'PY' "$RUN_DIR" "$BASE" >>"$RUN_DIR/summary.txt" 2>&1 || true
import sys, re
from pathlib import Path
from datetime import datetime

run_dir = Path(sys.argv[1])
base = Path(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[2] else None

def parse_snmp_windows(snmp_path: Path):
    re_line = re.compile(r'^(?P<ts>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\+\d{2}:\d{2}.*?\bmode=(?P<mode>\d+)\b.*?\bfr=(?P<fr>\d+)\b')
    rows=[]
    for ln in snmp_path.read_text(errors='replace').splitlines():
        m=re_line.search(ln)
        if not m: 
            continue
        ts=datetime.fromisoformat(m.group('ts'))
        rows.append((ts,int(m.group('mode')),int(m.group('fr'))))
    rows.sort()
    def windows(pred):
        out=[]
        start=None
        prev=None
        for ts,mode,fr in rows:
            ok=pred(mode,fr)
            if ok and start is None:
                start=ts
            if (not ok) and start is not None:
                out.append((start,prev))
                start=None
            prev=ts
        if start is not None and rows:
            out.append((start,rows[-1][0]))
        return out
    return rows, windows(lambda m,f: m==3), windows(lambda m,f: m==1 and f==0), windows(lambda m,f: f!=0)

def parse_stat_samples(utmc_follow: Path):
    # Extract STAT frames for stageCounter/transition if present.
    # Example: '#15:16:05 STAT (137) ... 173 10 255 10 0 3 0 0 0$90'
    # We keep raw rows; mapping fields can be DK-specific.
    out=[]
    re_stat = re.compile(r'^(?P<iso>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\+\d{4} .*?STAT .*?')
    for ln in utmc_follow.read_text(errors='replace').splitlines():
        m=re_stat.search(ln)
        if not m:
            continue
        ts=datetime.fromisoformat(m.group('iso'))
        out.append((ts,ln))
    return out

print("\n== Analysis ==")
if not base or not base.exists():
    print("no_base_dir")
    sys.exit(0)

snmp = base / "snmp_poll.log"
utmc = base / "spectr_utmc_follow.log"
resident = base / "resident_follow.log"

if snmp.exists():
    rows, w_mode3, w_norm, w_fr = parse_snmp_windows(snmp)
    print(f"snmp_samples={len(rows)}")
    print("mode=3 windows:")
    for a,b in w_mode3[:20]:
        print(f"  {a.time()} .. {b.time()}  dur_s={(b-a).total_seconds():.1f}")
    print("normal windows (mode=1, fr=0):")
    for a,b in w_norm[:20]:
        print(f"  {a.time()} .. {b.time()}  dur_s={(b-a).total_seconds():.1f}")
    print("fr!=0 windows:")
    for a,b in w_fr[:20]:
        print(f"  {a.time()} .. {b.time()}  dur_s={(b-a).total_seconds():.1f}")
else:
    print("snmp_poll.log missing")

if resident.exists():
    txt = resident.read_text(errors='replace')
    print(f"resident_contains_flashing_yellow={'Flashing yellow' in txt}")
else:
    print("resident_follow.log missing")

if utmc.exists():
    stats = parse_stat_samples(utmc)
    print(f"stat_samples={len(stats)}")
else:
    print("spectr_utmc_follow.log missing")
PY

DST="$ROOT_DIR/spectr_utmc/controller_snapshot/experiments/$(date +%Y-%m-%d_%H%M%S)_yf_plan_full"
mkdir -p "$DST"
cp -a "$RUN_DIR/"* "$DST/" || true
echo "dst=$DST" | tee -a "$RUN_DIR/summary.txt"
echo "$DST"
