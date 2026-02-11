#!/bin/bash
#
# Простой тест прямой работы с контроллером через SNMP
# Без промежуточных серверов, напрямую отправка команд
#

CONTROLLER_IP="192.168.75.150"
COMMUNITY="UTMC"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Прямой тест работы с контроллером через SNMP            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Контроллер: $CONTROLLER_IP"
echo "Community: $COMMUNITY"
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
# Проверка доступности контроллера
# ============================================================

log "=== Проверка доступности контроллера ==="
echo ""

if ! ping -c 1 -W 2 "$CONTROLLER_IP" >/dev/null 2>&1; then
    error "Контроллер недоступен (ping failed)"
    exit 1
fi
success "Контроллер доступен (ping OK)"

# Проверка SNMP доступности
log "Проверка SNMP доступности..."
if node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" --test 2>&1 | grep -q "Connection successful"; then
    success "SNMP доступен"
else
    error "SNMP недоступен"
    exit 1
fi

echo ""

# ============================================================
# Получение текущего состояния
# ============================================================

log "=== Текущее состояние контроллера ==="
echo ""

log "Режим работы..."
OPERATION_MODE=$(node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" --status 2>&1 | grep "Operation Mode" | grep -o "[0-9]")
MODE_NAMES=("Local" "Standalone" "Monitor" "UTC Control")
log "Режим: $OPERATION_MODE (${MODE_NAMES[$OPERATION_MODE]})"

log "Режим мигания (utcReplyFR)..."
FLASHING_MODE=$(node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
    --raw-get "1.3.6.1.4.1.13267.3.2.5.1.1.36" 2>&1 | grep -o "Value: [0-9]*" | cut -d' ' -f2 || echo "0")
log "Мигание: $FLASHING_MODE (0=выкл, 1=вкл)"

log "Текущая фаза..."
PHASE_HEX=$(node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" --status 2>&1 | grep "Current Stage" | grep -o "0x[0-9A-Fa-f]*" | head -1)
if [ -n "$PHASE_HEX" ]; then
    log "Фаза: $PHASE_HEX"
else
    log "Фаза: не определена"
fi

echo ""

# ============================================================
# Перевод в режим UTC Control (если нужно)
# ============================================================

if [ "$OPERATION_MODE" != "3" ]; then
    log "=== Перевод в режим UTC Control ==="
    echo ""
    
    log "Установка режима UTC Control (3)..."
    RESULT=$(node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
        --raw-set "1.3.6.1.4.1.13267.3.2.4.1" --value 3 --type Integer \
        --verbose 2>&1 | grep -E "(SET|success|Failed)")
    
    if echo "$RESULT" | grep -q "success"; then
        success "Режим установлен"
        log "Ожидание стабилизации (3 секунды)..."
        sleep 3
        
        # Проверка
        NEW_MODE=$(node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" --status 2>&1 | grep "Operation Mode" | grep -o "[0-9]")
        if [ "$NEW_MODE" = "3" ]; then
            success "Режим подтверждён: UTC Control (3)"
        else
            warning "Режим не подтверждён (получен: $NEW_MODE)"
        fi
    else
        error "Ошибка установки режима"
        exit 1
    fi
    
    echo ""
fi

# ============================================================
# Активация жёлтого мигания
# ============================================================

log "=== Активация жёлтого мигания ==="
echo ""
warning "⚠️  ВНИМАНИЕ: Будет активировано жёлтое мигание!"
warning "⚠️  Все светофоры на перекрёстке будут мигать жёлтым!"
warning "⚠️  Визуально контролируйте контроллер!"
echo ""
log "Начинаем через 3 секунды..."
sleep 3

# Отправка команды SET_YF (как в Node.js: operationMode=3, utcControlFF=1)
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
log "Ожидание активации мигания (5 секунд)..."
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
    echo ""
    warning "✓ ВИЗУАЛЬНО ПРОВЕРЬТЕ: Все светофоры должны мигать жёлтым!"
    echo ""
else
    warning "Мигание НЕ активировано (utcReplyFR=$FR_VALUE)"
    echo ""
    log "Возможные причины:"
    echo "  1. Контроллер принимает команды только от локального сервиса (127.0.0.1)"
    echo "  2. Требуется дополнительная настройка или условие"
    echo "  3. Контроллер в защищённом режиме"
    echo ""
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
log "возможно, контроллер принимает команды только от локального сервиса."
