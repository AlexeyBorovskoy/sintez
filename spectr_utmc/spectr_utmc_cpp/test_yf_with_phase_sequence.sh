#!/bin/bash
#
# Тест активации жёлтого мигания с правильной последовательностью команд
# Сначала устанавливаем фазу, затем активируем мигание
# БЕЗ автоматического отключения - режим ЖМ должен оставаться активным
#

CONTROLLER_IP="192.168.75.150"
COMMUNITY="UTMC"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Тест активации ЖМ с правильной последовательностью      ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Контроллер: $CONTROLLER_IP"
echo "Логика: Фаза → Мигание (БЕЗ автоматического отключения)"
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
log "Режим: $OPERATION_MODE (${MODE_NAMES[$OPERATION_MODE]})"

log "Текущая фаза..."
PHASE_HEX=$(node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" --status 2>&1 | grep "Current Stage" | grep -o "0x[0-9A-Fa-f]*" | head -1)
if [ -n "$PHASE_HEX" ]; then
    log "Фаза: $PHASE_HEX"
else
    log "Фаза: не определена"
fi

log "Режим мигания (utcReplyFR)..."
FLASHING_MODE=$(node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
    --raw-get "1.3.6.1.4.1.13267.3.2.5.1.1.36" 2>&1 | grep -o "Value: [0-9]*" | cut -d' ' -f2 || echo "0")
log "Мигание: $FLASHING_MODE (0=выкл, 1=вкл)"

echo ""

# ============================================================
# Перевод в режим UTC Control
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
    else
        error "Ошибка установки режима"
        exit 1
    fi
    
    echo ""
fi

# ============================================================
# Установка специальной фазы (фаза 1)
# ============================================================

log "=== Установка специальной фазы (фаза 1) ==="
echo ""

log "Установка фазы 1..."
RESULT=$(node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
    --raw-set "1.3.6.1.4.1.13267.3.2.4.1" --value 3 --type Integer \
    --raw-set "1.3.6.1.4.1.13267.3.2.4.2.1.5" --value "01" --type HexString \
    --verbose 2>&1 | grep -E "(SET|success|Failed)")

if echo "$RESULT" | grep -q "success"; then
    success "Фаза 1 установлена"
    log "Ожидание активации фазы (5 секунд)..."
    sleep 5
    
    # Проверка фазы
    NEW_PHASE=$(node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" --status 2>&1 | grep "Current Stage" | grep -o "0x[0-9A-Fa-f]*" | head -1)
    if [ -n "$NEW_PHASE" ]; then
        log "Новая фаза: $NEW_PHASE"
    fi
else
    error "Ошибка установки фазы"
    exit 1
fi

echo ""

# ============================================================
# Ожидание минимального периода работы фазы
# ============================================================

log "=== Ожидание минимального периода работы фазы ==="
echo ""

log "Получение информации о длительности фазы..."
STAGE_LENGTH=$(node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
    --raw-get "1.3.6.1.4.1.13267.3.2.5.1.1.4" 2>&1 | grep -o "Value: [0-9]*" | cut -d' ' -f2 || echo "0")

STAGE_COUNTER=$(node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
    --raw-get "1.3.6.1.4.1.13267.3.2.5.1.1.5" 2>&1 | grep -o "Value: [0-9]*" | cut -d' ' -f2 || echo "0")

if [ -n "$STAGE_LENGTH" ] && [ -n "$STAGE_COUNTER" ]; then
    log "Длительность фазы: $STAGE_LENGTH сек, счётчик: $STAGE_COUNTER сек"
    
    # Минимальное время = 50% от длительности или минимум 5 секунд
    MIN_TIME=$((STAGE_LENGTH / 2))
    if [ $MIN_TIME -lt 5 ]; then
        MIN_TIME=5
    fi
    
    if [ "$STAGE_COUNTER" -lt "$MIN_TIME" ]; then
        WAIT_TIME=$((MIN_TIME - STAGE_COUNTER + 3))  # +3 сек безопасности
        log "Ожидание истечения минимального периода: $WAIT_TIME сек (прошло: $STAGE_COUNTER сек, требуется: $MIN_TIME сек)"
        sleep $WAIT_TIME
        success "Минимальный период истёк"
    else
        success "Минимальный период уже истёк"
    fi
else
    warning "Не удалось получить информацию о длительности фазы, используем стандартное ожидание (10 сек)"
    sleep 10
fi

echo ""

# ============================================================
# Активация жёлтого мигания
# ============================================================

log "=== Активация жёлтого мигания ==="
echo ""
warning "⚠️  ВНИМАНИЕ: Будет активировано жёлтое мигание!"
warning "⚠️  Все светофоры на перекрёстке будут мигать жёлтым!"
warning "⚠️  Режим ЖМ НЕ будет отключаться автоматически!"
warning "⚠️  Визуально контролируйте контроллер!"
echo ""
log "Начинаем активацию через 3 секунды..."
sleep 3

# Отправка команды SET_YF (operationMode=3, utcControlFF=1)
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
    echo "  1. Требуется дополнительная последовательность команд"
    echo "  2. Контроллер требует других условий для активации"
    echo "  3. Команды принимаются только от локального сервиса (127.0.0.1)"
    echo ""
fi

log "Проверка режима работы..."
FINAL_MODE=$(node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" --status 2>&1 | grep "Operation Mode" | grep -o "[0-9]")
log "Финальный режим: $FINAL_MODE (${MODE_NAMES[$FINAL_MODE]})"

log "Проверка текущей фазы..."
FINAL_PHASE=$(node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" --status 2>&1 | grep "Current Stage" | grep -o "0x[0-9A-Fa-f]*" | head -1)
if [ -n "$FINAL_PHASE" ]; then
    log "Финальная фаза: $FINAL_PHASE"
fi

echo ""
log "=== Тест завершён ==="
echo ""
warning "ВАЖНО:"
echo "  - Режим ЖМ НЕ отключается автоматически"
echo "  - Для отключения нужна команда на переход на другую программу управления"
echo "  - Проверьте визуально на контроллере: активировалось ли жёлтое мигание?"
echo ""
log "Для отключения мигания используйте команду SET_PHASE или другую команду управления"
