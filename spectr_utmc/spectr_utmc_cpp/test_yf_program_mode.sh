#!/bin/bash
set -u
BIN="/home/alexey/shared_vm/spectr_utmc/spectr_utmc/spectr_utmc_cpp/build/test_controller"
IP="192.168.75.150"
COMM="UTMC"
LOG="/tmp/test_yf_program_mode.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }
get_oid() { "$BIN" get "$IP" "$COMM" "$1" 2>&1 | tee -a "$LOG"; }
set_multi() { "$BIN" setmulti "$IP" "$COMM" "$@" 2>&1 | tee -a "$LOG"; }

: > "$LOG"
log "=== BASELINE ==="
get_oid "1.3.6.1.4.1.13267.3.2.4.1"
get_oid "1.3.6.1.4.1.13267.3.2.5.1.1.36"

# Helper: set opMode=3 then a control bit, then FF=1, then poll FR, then reset control bit to 0
try_control_bit() {
  local name="$1"
  local oid="$2"
  log "=== TRY ${name} (set 1) -> SET_YF ==="
  set_multi \
    1.3.6.1.4.1.13267.3.2.4.1 2 3 \
    "$oid" 2 1
  sleep 2
  set_multi \
    1.3.6.1.4.1.13267.3.2.4.1 2 3 \
    1.3.6.1.4.1.13267.3.2.4.2.1.20 2 1
  sleep 2
  get_oid "1.3.6.1.4.1.13267.3.2.5.1.1.36"
  log "=== RESET ${name} to 0 ==="
  set_multi \
    1.3.6.1.4.1.13267.3.2.4.1 2 3 \
    "$oid" 2 0
  sleep 1
}

# Control bits (from MIB utcControlEntry)
try_control_bit "utcControlSO" "1.3.6.1.4.1.13267.3.2.4.2.1.9"
try_control_bit "utcControlSG" "1.3.6.1.4.1.13267.3.2.4.2.1.10"
try_control_bit "utcControlLO" "1.3.6.1.4.1.13267.3.2.4.2.1.11"
try_control_bit "utcControlLL" "1.3.6.1.4.1.13267.3.2.4.2.1.12"
try_control_bit "utcControlTS" "1.3.6.1.4.1.13267.3.2.4.2.1.13"
try_control_bit "utcControlFM" "1.3.6.1.4.1.13267.3.2.4.2.1.14"
try_control_bit "utcControlTO" "1.3.6.1.4.1.13267.3.2.4.2.1.15"
try_control_bit "utcControlHI" "1.3.6.1.4.1.13267.3.2.4.2.1.16"
try_control_bit "utcControlCP" "1.3.6.1.4.1.13267.3.2.4.2.1.17"
try_control_bit "utcControlEP" "1.3.6.1.4.1.13267.3.2.4.2.1.18"
try_control_bit "utcControlGO" "1.3.6.1.4.1.13267.3.2.4.2.1.19"
try_control_bit "utcControlMO" "1.3.6.1.4.1.13267.3.2.4.2.1.21"

log "=== CLEANUP FF=0 ==="
set_multi \
  1.3.6.1.4.1.13267.3.2.4.1 2 3 \
  1.3.6.1.4.1.13267.3.2.4.2.1.20 2 0
sleep 1
get_oid "1.3.6.1.4.1.13267.3.2.5.1.1.36"

log "=== DONE ==="
log "Log: $LOG"
