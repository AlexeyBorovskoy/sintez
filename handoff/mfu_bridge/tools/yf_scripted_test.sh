#!/usr/bin/env bash
set -euo pipefail

# Сценарный прогон ЖМ через локальный SNMP на контроллере (SSH + snmpget/snmpset на 127.0.0.1).
# Скрипт снимает логи через tools/dk_capture.sh и формирует MD-отчет.
#
# Сценарий:
#  1) Включить ЖМ на 60с
#  2) Вернуть штатный режим
#  3) Подождать 120с
#  4) Включить ЖМ на 60с
#  5) Вернуть штатный режим
#
# Использование:
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
Использование: DK_PASS=... $0 [опции]

Опции:
  --ip <ip>                 (по умолчанию: $IP)
  --user <user>             (по умолчанию: $USER)
  --comm <community>        (по умолчанию: $COMM)
  --yf-enable-timeout <sec> (по умолчанию: $YF_ENABLE_TIMEOUT_SEC)
  --yf-set-period <sec>     (по умолчанию: $YF_SET_PERIOD_SEC)
  --yf-hold <sec>           (по умолчанию: $YF_HOLD_SEC)
  --between <sec>           (по умолчанию: $BETWEEN_SEC)
  --confirm                 Обязательно. Без этого флага скрипт только покажет сценарий и завершится.
EOF
      exit 0
      ;;
    *)
      echo "ошибка: неизвестный аргумент: $1" >&2
      exit 2
      ;;
  esac
done

[[ -n "${DK_PASS:-}" ]] || { echo "ошибка: требуется DK_PASS" >&2; exit 2; }

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
Планируемый сценарий (dry run; команды на контроллер НЕ выполняются):
1) Включить ЖМ и подтвердить по utcReplyFR (таймаут: ${YF_ENABLE_TIMEOUT_SEC}с)
2) Удерживать ЖМ ${YF_HOLD_SEC}с (переотправка SetAF=1 каждые ${YF_SET_PERIOD_SEC}с)
3) Вернуть штатный режим (mode=1, FF=0, LO=0)
4) Подождать ${BETWEEN_SEC}с
5) Снова включить ЖМ и удерживать ${YF_HOLD_SEC}с
6) Вернуть штатный режим

Чтобы реально выполнить сценарий: добавьте --confirm
Каталог вывода: ${RUN_DIR}
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
  # Один раз перейти в UTC control, затем переотправлять FF=1 пока FR==1 или не истечет таймаут.
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
      log "ОШИБКА: таймаут enable_yf (нет подтверждения utcReplyFR)"
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

log "ШАГ 1: включение ЖМ"
enable_yf_until_confirm
log "ШАГ 1: удержание ЖМ ${YF_HOLD_SEC}с (переотправка FF=1)"
hold_start="$(date +%s)"
while [[ $(( $(date +%s) - hold_start )) -lt "$YF_HOLD_SEC" ]]; do
  remote "set -euo pipefail; snmpset -v1 -c \"\$COMM\" -t 2 -r 1 -Oqv 127.0.0.1 $OID_FF i 1 >/dev/null; echo ff_keep_1" >>"$SCENARIO_LOG" 2>&1 || true
  sleep "$YF_SET_PERIOD_SEC"
done

log "ШАГ 2: возврат в штатный режим"
restore_normal >>"$SCENARIO_LOG" 2>&1 || true

log "ШАГ 3: ожидание ${BETWEEN_SEC}с"
sleep "$BETWEEN_SEC"

log "ШАГ 4: повторное включение ЖМ"
enable_yf_until_confirm
log "ШАГ 4: удержание ЖМ ${YF_HOLD_SEC}с (переотправка FF=1)"
hold_start="$(date +%s)"
while [[ $(( $(date +%s) - hold_start )) -lt "$YF_HOLD_SEC" ]]; do
  remote "set -euo pipefail; snmpset -v1 -c \"\$COMM\" -t 2 -r 1 -Oqv 127.0.0.1 $OID_FF i 1 >/dev/null; echo ff_keep_1" >>"$SCENARIO_LOG" 2>&1 || true
  sleep "$YF_SET_PERIOD_SEC"
done

log "ШАГ 5: возврат в штатный режим"
restore_normal >>"$SCENARIO_LOG" 2>&1 || true

log "ОСТАНОВ захвата + выгрузка"
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
