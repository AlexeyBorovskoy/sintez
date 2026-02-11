#!/bin/bash
set -u
BIN="/home/alexey/shared_vm/spectr_utmc/spectr_utmc/spectr_utmc_cpp/build/test_controller"
IP="192.168.75.150"
COMM="UTMC"
LOG="/tmp/test_yf_node_parity.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }
get_oid() { "$BIN" get "$IP" "$COMM" "$1" 2>&1 | tee -a "$LOG"; }
set_multi() { "$BIN" setmulti "$IP" "$COMM" "$@" 2>&1 | tee -a "$LOG"; }

make_byte() {
  local dec="$1"
  local hex
  hex=$(printf '%02x' "$dec")
  printf '%b' "\\x$hex"
}

: > "$LOG"
log "=== BASELINE ==="
get_oid "1.3.6.1.4.1.13267.3.2.4.1"
get_oid "1.3.6.1.4.1.13267.3.2.5.1.1.3"
get_oid "1.3.6.1.4.1.13267.3.2.5.1.1.36"

log "=== A: NODE-STYLE SET_YF (opMode + FF) ==="
set_multi \
  1.3.6.1.4.1.13267.3.2.4.1 2 3 \
  1.3.6.1.4.1.13267.3.2.4.2.1.20 2 1
sleep 2
get_oid "1.3.6.1.4.1.13267.3.2.5.1.1.36"

log "=== B: SET_LOCAL -> SET_YF ==="
set_multi \
  1.3.6.1.4.1.13267.3.2.4.2.1.11 2 0 \
  1.3.6.1.4.1.13267.3.2.4.2.1.20 2 0 \
  1.3.6.1.4.1.13267.3.2.4.1 2 1
sleep 2
set_multi \
  1.3.6.1.4.1.13267.3.2.4.1 2 3 \
  1.3.6.1.4.1.13267.3.2.4.2.1.20 2 1
sleep 2
get_oid "1.3.6.1.4.1.13267.3.2.5.1.1.36"

log "=== C: SET_START -> SET_YF ==="
set_multi \
  1.3.6.1.4.1.13267.3.2.4.2.1.5.5 2 1 \
  1.3.6.1.4.1.13267.3.2.4.1 2 1
sleep 2
set_multi \
  1.3.6.1.4.1.13267.3.2.4.1 2 3 \
  1.3.6.1.4.1.13267.3.2.4.2.1.20 2 1
sleep 2
get_oid "1.3.6.1.4.1.13267.3.2.5.1.1.36"

log "=== D: SET_PHASE 1 (octet) -> wait 12s -> SET_YF ==="
phase_val=$(make_byte 1)
set_multi \
  1.3.6.1.4.1.13267.3.2.4.1 2 3 \
  1.3.6.1.4.1.13267.3.2.4.2.1.5 4 "$phase_val"
get_oid "1.3.6.1.4.1.13267.3.2.5.1.1.3"
sleep 12
set_multi \
  1.3.6.1.4.1.13267.3.2.4.1 2 3 \
  1.3.6.1.4.1.13267.3.2.4.2.1.20 2 1
sleep 2
get_oid "1.3.6.1.4.1.13267.3.2.5.1.1.36"

log "=== E: HOLD SET_YF 30s (every 2s) ==="
for i in $(seq 1 15); do
  log "hold $i"
  set_multi \
    1.3.6.1.4.1.13267.3.2.4.1 2 3 \
    1.3.6.1.4.1.13267.3.2.4.2.1.20 2 1
  sleep 2
  if (( i % 5 == 0 )); then
    get_oid "1.3.6.1.4.1.13267.3.2.5.1.1.36"
  fi
  done

log "=== F: SET_OS -> SET_YF ==="
set_multi \
  1.3.6.1.4.1.13267.3.2.4.1 2 3 \
  1.3.6.1.4.1.13267.3.2.4.2.1.11 2 1
sleep 2
set_multi \
  1.3.6.1.4.1.13267.3.2.4.1 2 3 \
  1.3.6.1.4.1.13267.3.2.4.2.1.20 2 1
sleep 2
get_oid "1.3.6.1.4.1.13267.3.2.5.1.1.36"

log "=== G: OBSERVE AFTER SET_YF (20s polling) ==="
set_multi \
  1.3.6.1.4.1.13267.3.2.4.1 2 3 \
  1.3.6.1.4.1.13267.3.2.4.2.1.20 2 1
for i in $(seq 1 10); do
  sleep 2
  log "poll $i"
  get_oid "1.3.6.1.4.1.13267.3.2.5.1.1.36"
  get_oid "1.3.6.1.4.1.13267.3.2.4.1"
  done

log "=== CLEANUP FF=0 ==="
set_multi \
  1.3.6.1.4.1.13267.3.2.4.1 2 3 \
  1.3.6.1.4.1.13267.3.2.4.2.1.20 2 0
sleep 1
get_oid "1.3.6.1.4.1.13267.3.2.5.1.1.36"

log "=== DONE ==="
log "Log: $LOG"
