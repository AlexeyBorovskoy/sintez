#!/bin/bash
#
# Простой тест жёлтого мигания - точная копия логики Node.js
# Отправляет команду один раз, без предварительных проверок
#

CONTROLLER_IP="192.168.75.150"
COMMUNITY="UTMC"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Простой тест жёлтого мигания (логика Node.js)           ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Контроллер: $CONTROLLER_IP"
echo "Логика: Точная копия Node.js SET_YF (одна команда, без проверок)"
echo ""

cd "$SCRIPT_DIR/../AI_reaserh" || exit 1

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

# ============================================================
# Проверка текущего состояния
# ============================================================

log "=== Проверка текущего состояния ==="
echo ""

log "Режим работы..."
OPERATION_MODE=$(node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" --status 2>&1 | grep "Operation Mode" | grep -o "[0-9]")
MODE_NAMES=("Local" "Standalone" "Monitor" "UTC Control")
log "Текущий режим: $OPERATION_MODE (${MODE_NAMES[$OPERATION_MODE]})"

log "Режим мигания (utcReplyFR)..."
FLASHING_MODE=$(node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
    --raw-get "1.3.6.1.4.1.13267.3.2.5.1.1.36" 2>&1 | grep -o "Value: [0-9]*" | cut -d' ' -f2 || echo "0")
log "Режим мигания: $FLASHING_MODE"

echo ""

# ============================================================
# Отправка команды SET_YF (как в Node.js)
# ============================================================

log "=== Отправка команды SET_YF (логика Node.js) ==="
echo ""
warning "⚠️  ВНИМАНИЕ: Будет отправлена команда SET_YF!"
warning "⚠️  Все светофоры на перекрёстке должны мигать жёлтым!"
warning "⚠️  Визуально контролируйте контроллер!"
echo ""
log "Начинаем через 3 секунды..."
sleep 3

# Точная копия Node.js SET_YF:
# - operationMode = 3 (UTC Control)
# - utcControlFF = 1 (включить мигание)
# - Одна команда, без проверок, без удержания

log "Отправка команды SET_YF..."
RESULT=$(node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
    --raw-set "1.3.6.1.4.1.13267.3.2.4.1" --value 3 --type Integer \
    --raw-set "1.3.6.1.4.1.13267.3.2.4.2.1.20" --value 1 --type Integer \
    --verbose 2>&1)

echo "$RESULT" | grep -E "(SET|success|Failed|error)" || echo "$RESULT"

if echo "$RESULT" | grep -q "success"; then
    success "Команда отправлена успешно"
else
    error "Ошибка отправки команды"
    exit 1
fi

echo ""
log "Ожидание 5 секунд для активации мигания..."
sleep 5

# ============================================================
# Проверка результата
# ============================================================

log "=== Проверка результата ==="
echo ""

log "Проверка режима мигания (utcReplyFR)..."
FR_VALUE=$(node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
    --raw-get "1.3.6.1.4.1.13267.3.2.5.1.1.36" 2>&1 | grep -o "Value: [0-9]*" | cut -d' ' -f2 || echo "0")

if [ "$FR_VALUE" = "1" ]; then
    success "Мигание АКТИВИРОВАНО! (utcReplyFR=1)"
else
    warning "Мигание НЕ активировано (utcReplyFR=$FR_VALUE)"
fi

log "Проверка режима работы..."
FINAL_MODE=$(node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" --status 2>&1 | grep "Operation Mode" | grep -o "[0-9]")
log "Финальный режим: $FINAL_MODE (${MODE_NAMES[$FINAL_MODE]})"

echo ""
log "=== Тест завершён ==="
echo ""
warning "ВАЖНО: Проверьте визуально на контроллере:"
echo "  - Активировалось ли жёлтое мигание всех светофоров?"
echo "  - Работает ли мигание сейчас?"
echo ""
log "Если мигание не активировалось визуально, но команда отправлена успешно,"
log "возможные причины:"
echo "  1. Контроллер требует дополнительных условий (режим, фаза, время)"
echo "  2. Контроллер имеет защиту от удалённого управления"
echo "  3. Контроллер требует другую последовательность команд"
