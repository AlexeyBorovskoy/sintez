#!/bin/bash
#
# Тест жёлтого мигания через протокол Spectr-ITS
# Имитирует работу АСУДД: отправка команды через TCP/IP на spectr_utmc.js
#

CONTROLLER_IP="192.168.75.150"
SPECTR_ITS_PORT="3000"  # Порт для протокола Spectr-ITS (из config.json)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Тест жёлтого мигания через протокол Spectr-ITS          ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Контроллер: $CONTROLLER_IP"
echo "Порт Spectr-ITS: $SPECTR_ITS_PORT"
echo "Логика: АСУДД → TCP/IP (Spectr-ITS) → spectr_utmc.js → SNMP → контроллер"
echo ""

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $1"
}

success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Функция для вычисления checksum
calculate_checksum() {
    local data="$1"
    local sum=0
    for ((i=0; i<${#data}; i++)); do
        sum=$((sum + $(printf '%d' "'${data:$i:1}")))
        if [ $((sum & 0x100)) -ne 0 ]; then
            sum=$((sum + 1))
        fi
        sum=$((sum & 0xFF))
    done
    printf "%02x" $sum
}

# Функция для форматирования команды Spectr-ITS
format_command() {
    local command="$1"
    local request_id="${2:-TEST001}"
    local time=$(date +%H:%M:%S)
    
    # Формат: #TIME COMMAND REQUEST_ID$XX\r
    local data="#${time} ${command} ${request_id}"
    local checksum=$(calculate_checksum "$data")
    echo "${data}\$${checksum}\r"
}

# ============================================================
# Проверка доступности порта Spectr-ITS
# ============================================================

log "=== Проверка доступности порта Spectr-ITS ==="
echo ""

if ! timeout 2 bash -c "echo > /dev/tcp/$CONTROLLER_IP/$SPECTR_ITS_PORT" 2>/dev/null; then
    error "Порт $SPECTR_ITS_PORT на $CONTROLLER_IP недоступен!"
    warning "Возможно, spectr_utmc.js не работает на контроллере"
    warning "Или порт отличается от указанного в config.json"
    echo ""
    log "Проверяю альтернативные порты..."
    
    for port in 3000 10162 161 162; do
        if timeout 1 bash -c "echo > /dev/tcp/$CONTROLLER_IP/$port" 2>/dev/null; then
            log "Порт $port доступен"
        fi
    done
    
    echo ""
    warning "Продолжаем тест, но команда может не дойти до контроллера"
    echo ""
else
    success "Порт $SPECTR_ITS_PORT доступен"
fi

echo ""

# ============================================================
# Отправка команды SET_YF через протокол Spectr-ITS
# ============================================================

log "=== Отправка команды SET_YF через протокол Spectr-ITS ==="
echo ""
warning "⚠️  ВНИМАНИЕ: Будет отправлена команда SET_YF через протокол Spectr-ITS!"
warning "⚠️  Все светофоры на перекрёстке должны мигать жёлтым!"
warning "⚠️  Визуально контролируйте контроллер!"
echo ""
log "Начинаем через 3 секунды..."
sleep 3

# Формирование команды SET_YF
REQUEST_ID="TEST$(date +%s)"
COMMAND=$(format_command "SET_YF" "$REQUEST_ID")

log "Отправка команды:"
echo "  Команда: SET_YF"
echo "  Request ID: $REQUEST_ID"
echo "  Формат: $COMMAND"
echo ""

# Отправка команды через TCP/IP
RESPONSE=$(echo -ne "$COMMAND" | timeout 5 nc "$CONTROLLER_IP" "$SPECTR_ITS_PORT" 2>&1)

if [ $? -eq 0 ] && [ -n "$RESPONSE" ]; then
    success "Получен ответ от контроллера:"
    echo "  $RESPONSE"
else
    if [ $? -eq 124 ]; then
        warning "Таймаут ожидания ответа (5 секунд)"
    else
        warning "Не получен ответ от контроллера"
        warning "Возможно, spectr_utmc.js не работает на контроллере"
        warning "Или порт отличается от указанного"
    fi
fi

echo ""
log "Ожидание 5 секунд для активации мигания..."
sleep 5

# ============================================================
# Проверка результата через SNMP
# ============================================================

log "=== Проверка результата через SNMP ==="
echo ""

cd "$SCRIPT_DIR/../AI_reaserh" || exit 1

log "Проверка режима мигания (utcReplyFR)..."
FR_VALUE=$(node utmc-tester.js --ip "$CONTROLLER_IP" --community "UTMC" \
    --raw-get "1.3.6.1.4.1.13267.3.2.5.1.1.36" 2>&1 | grep -o "Value: [0-9]*" | cut -d' ' -f2 || echo "0")

if [ "$FR_VALUE" = "1" ]; then
    success "Мигание АКТИВИРОВАНО! (utcReplyFR=1)"
else
    warning "Мигание НЕ активировано (utcReplyFR=$FR_VALUE)"
fi

log "Проверка режима работы..."
FINAL_MODE=$(node utmc-tester.js --ip "$CONTROLLER_IP" --community "UTMC" --status 2>&1 | grep "Operation Mode" | grep -o "[0-9]")
MODE_NAMES=("Local" "Standalone" "Monitor" "UTC Control")
log "Финальный режим: $FINAL_MODE (${MODE_NAMES[$FINAL_MODE]})"

echo ""
log "=== Тест завершён ==="
echo ""
warning "ВАЖНО: Проверьте визуально на контроллере:"
echo "  - Активировалось ли жёлтое мигание всех светофоров?"
echo "  - Работает ли мигание сейчас?"
echo ""
log "Если порт Spectr-ITS недоступен, это означает, что:"
echo "  1. spectr_utmc.js не работает на контроллере"
echo "  2. Порт отличается от указанного в config.json"
echo "  3. Контроллер не принимает внешние TCP соединения"
echo ""
log "В этом случае команды нужно отправлять напрямую по SNMP,"
log "но возможно, контроллер принимает команды только от локального сервиса (127.0.0.1)"
