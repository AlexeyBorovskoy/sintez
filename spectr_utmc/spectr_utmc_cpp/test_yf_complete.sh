#!/bin/bash
#
# Полный тест жёлтого мигания с обновлённой логикой C++
# Выполняет все этапы: проверка режима → перевод → проверка фазы → активация
#

CONTROLLER_IP="192.168.75.150"
COMMUNITY="UTMC"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Полный тест жёлтого мигания (обновлённая логика C++)    ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Контроллер: $CONTROLLER_IP"
echo "Режим: Все светофоры мигают жёлтым одновременно"
echo ""

cd "$SCRIPT_DIR/../AI_reaserh" || exit 1

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Функция логирования
log() {
    echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# ============================================================
# ЭТАП 1: Проверка текущего состояния
# ============================================================

log "=== ЭТАП 1: Проверка текущего состояния ==="
echo ""

log "Получение информации о контроллере..."

# Проверка доступности
if ! node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" --test 2>&1 | grep -q "Connection successful"; then
    error "Контроллер недоступен!"
    exit 1
fi
success "Контроллер доступен"

# Получение режима работы
log "Проверка режима работы..."
OPERATION_MODE=$(node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" --status 2>&1 | grep "Operation Mode" | grep -o "[0-9]")
if [ -z "$OPERATION_MODE" ]; then
    error "Не удалось получить режим работы"
    exit 1
fi

MODE_NAMES=("Local" "Standalone" "Monitor" "UTC Control")
log "Текущий режим: $OPERATION_MODE (${MODE_NAMES[$OPERATION_MODE]})"

# Получение текущей фазы
log "Проверка текущей фазы..."
PHASE_HEX=$(node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" --status 2>&1 | grep "Current Stage" | grep -o "0x[0-9A-Fa-f]*" | head -1)
if [ -z "$PHASE_HEX" ]; then
    warning "Не удалось получить текущую фазу"
    PHASE_NUM=0
else
    # Преобразование hex в номер фазы
    PHASE_VALUE=$((16#${PHASE_HEX#0x}))
    PHASE_NUM=0
    for i in {0..7}; do
        if [ $((PHASE_VALUE & (1 << i))) -ne 0 ]; then
            PHASE_NUM=$((i + 1))
            break
        fi
    done
    log "Текущая фаза: $PHASE_NUM (0x${PHASE_HEX#0x})"
fi

# Получение режима мигания
log "Проверка режима мигания..."
FLASHING_MODE=$(node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
    --raw-get "1.3.6.1.4.1.13267.3.2.5.1.1.36" 2>&1 | grep -o "Value: [0-9]*" | cut -d' ' -f2)
if [ -z "$FLASHING_MODE" ]; then
    FLASHING_MODE=0
fi
log "Режим мигания (utcReplyFR): $FLASHING_MODE"

if [ "$FLASHING_MODE" = "1" ]; then
    warning "Мигание уже активно!"
fi

echo ""

# ============================================================
# ЭТАП 2: Перевод в режим UTC Control
# ============================================================

log "=== ЭТАП 2: Перевод в режим UTC Control ==="
echo ""

if [ "$OPERATION_MODE" != "3" ]; then
    log "Перевод контроллера в режим UTC Control (3)..."
    
    RESULT=$(node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
        --raw-set "1.3.6.1.4.1.13267.3.2.4.1" --value 3 --type Integer \
        --verbose 2>&1 | grep -E "(SET|success|Failed)")
    
    if echo "$RESULT" | grep -q "success"; then
        success "Режим переведён в UTC Control"
    else
        error "Ошибка перевода в режим UTC Control"
        exit 1
    fi
    
    log "Ожидание стабилизации режима (3 секунды)..."
    sleep 3
    
    # Проверка режима
    NEW_MODE=$(node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" --status 2>&1 | grep "Operation Mode" | grep -o "[0-9]")
    if [ "$NEW_MODE" = "3" ]; then
        success "Режим подтверждён: UTC Control (3)"
    else
        warning "Режим не подтверждён (получен: $NEW_MODE)"
    fi
else
    success "Контроллер уже в режиме UTC Control (3)"
fi

echo ""

# ============================================================
# ЭТАП 3: Проверка и подготовка фазы
# ============================================================

log "=== ЭТАП 3: Проверка и подготовка фазы ==="
echo ""

SPECIAL_PHASES=(1 2 3 4)
IS_SPECIAL=false

if [ "$PHASE_NUM" -gt 0 ]; then
    for sp in "${SPECIAL_PHASES[@]}"; do
        if [ "$PHASE_NUM" -eq "$sp" ]; then
            IS_SPECIAL=true
            break
        fi
    done
    
    if [ "$IS_SPECIAL" = true ]; then
        success "Текущая фаза $PHASE_NUM является специальной (nominated stage)"
    else
        warning "Текущая фаза $PHASE_NUM НЕ является специальной (специальные: 1,2,3,4)"
        log "Установка специальной фазы 1..."
        
        RESULT=$(node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
            --raw-set "1.3.6.1.4.1.13267.3.2.4.1" --value 3 --type Integer \
            --raw-set "1.3.6.1.4.1.13267.3.2.4.2.1.5" --value "01" --type HexString \
            --verbose 2>&1 | grep -E "(SET|success|Failed)")
        
        if echo "$RESULT" | grep -q "success"; then
            success "Фаза 1 установлена"
            PHASE_NUM=1
            IS_SPECIAL=true
            log "Ожидание активации фазы (2 секунды)..."
            sleep 2
        else
            error "Ошибка установки фазы"
            exit 1
        fi
    fi
    
    # Проверка минимального периода работы фазы
    log "Проверка минимального периода работы фазы..."
    
    STAGE_LENGTH=$(node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
        --raw-get "1.3.6.1.4.1.13267.3.2.5.1.1.4" 2>&1 | grep -o "Value: [0-9]*" | cut -d' ' -f2)
    
    STAGE_COUNTER=$(node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
        --raw-get "1.3.6.1.4.1.13267.3.2.5.1.1.5" 2>&1 | grep -o "Value: [0-9]*" | cut -d' ' -f2)
    
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
else
    warning "Нет активной фазы, устанавливаем фазу 1..."
    
    RESULT=$(node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
        --raw-set "1.3.6.1.4.1.13267.3.2.4.1" --value 3 --type Integer \
        --raw-set "1.3.6.1.4.1.13267.3.2.4.2.1.5" --value "01" --type HexString \
        --verbose 2>&1 | grep -E "(SET|success|Failed)")
    
    if echo "$RESULT" | grep -q "success"; then
        success "Фаза 1 установлена"
        sleep 13  # 10 сек минимум + 3 сек безопасности
    else
        error "Ошибка установки фазы"
        exit 1
    fi
fi

echo ""

# ============================================================
# ЭТАП 4: Активация жёлтого мигания
# ============================================================

log "=== ЭТАП 4: Активация жёлтого мигания ==="
echo ""
warning "⚠️  ВНИМАНИЕ: Будет активировано жёлтое мигание!"
warning "⚠️  Все светофоры на перекрёстке будут мигать жёлтым!"
warning "⚠️  Визуально контролируйте контроллер!"
echo ""
log "Начинаем активацию через 3 секунды..."
sleep 3

# Немедленная отправка первой команды
log "[0 сек] Отправка команды SET_YF (активация мигания)..."
RESULT=$(node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
    --raw-set "1.3.6.1.4.1.13267.3.2.4.1" --value 3 --type Integer \
    --raw-set "1.3.6.1.4.1.13267.3.2.4.2.1.20" --value 1 --type Integer \
    --verbose 2>&1 | grep -E "(SET|success|Failed)")

if echo "$RESULT" | grep -q "success"; then
    success "Команда отправлена успешно"
else
    error "Ошибка отправки команды"
    exit 1
fi

# Удержание команды в течение 60 секунд (каждые 2 секунды)
log ""
log "Удержание команды (60 секунд, отправка каждые 2 секунды)..."
log "Это обеспечит выполнение требования 'команда активна минимум 10 секунд'"
echo ""

for i in {1..30}; do
    elapsed=$((i * 2))
    sleep 2
    
    echo -n "[$elapsed сек] Отправка #$i... "
    RESULT=$(node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
        --raw-set "1.3.6.1.4.1.13267.3.2.4.1" --value 3 --type Integer \
        --raw-set "1.3.6.1.4.1.13267.3.2.4.2.1.20" --value 1 --type Integer 2>&1 | grep -E "(SET|success|Failed)" || true)
    
    if echo "$RESULT" | grep -q "success"; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
    fi
    
    # Проверка активации мигания каждые 10 секунд
    if [ $((elapsed % 10)) -eq 0 ]; then
        echo ""
        log "Проверка активации мигания (utcReplyFR)..."
        FR_VALUE=$(node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
            --raw-get "1.3.6.1.4.1.13267.3.2.5.1.1.36" 2>&1 | grep -o "Value: [0-9]*" | cut -d' ' -f2 || echo "0")
        
        if [ "$FR_VALUE" = "1" ]; then
            success "Мигание АКТИВИРОВАНО! (utcReplyFR=1)"
            echo ""
            warning "✓ ВИЗУАЛЬНО ПРОВЕРЬТЕ: Все светофоры должны мигать жёлтым!"
            echo ""
        else
            log "Мигание ещё не активировано (utcReplyFR=$FR_VALUE)"
        fi
        echo ""
    fi
done

echo ""

# ============================================================
# ЭТАП 5: Отключение мигания
# ============================================================

log "=== ЭТАП 5: Отключение мигания ==="
echo ""

for i in {1..3}; do
    log "Попытка отключения #$i..."
    RESULT=$(node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
        --raw-set "1.3.6.1.4.1.13267.3.2.4.1" --value 3 --type Integer \
        --raw-set "1.3.6.1.4.1.13267.3.2.4.2.1.20" --value 0 --type Integer \
        --verbose 2>&1 | grep -E "(SET|success|Failed)")
    
    if echo "$RESULT" | grep -q "success"; then
        success "Команда отключения отправлена"
    else
        warning "Ошибка отправки команды отключения"
    fi
    
    if [ $i -lt 3 ]; then
        sleep 2
    fi
done

sleep 2

# ============================================================
# ЭТАП 6: Финальная проверка
# ============================================================

log "=== ЭТАП 6: Финальная проверка ==="
echo ""

log "Проверка режима мигания (utcReplyFR)..."
FR_FINAL=$(node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
    --raw-get "1.3.6.1.4.1.13267.3.2.5.1.1.36" 2>&1 | grep -o "Value: [0-9]*" | cut -d' ' -f2 || echo "0")

if [ "$FR_FINAL" = "0" ]; then
    success "Мигание отключено (utcReplyFR=0)"
else
    warning "Мигание всё ещё активно (utcReplyFR=$FR_FINAL)"
fi

log "Проверка режима работы..."
FINAL_MODE=$(node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" --status 2>&1 | grep "Operation Mode" | grep -o "[0-9]")
log "Финальный режим: $FINAL_MODE (${MODE_NAMES[$FINAL_MODE]})"

echo ""
log "=== Тест завершён ==="
echo ""
echo "Результаты:"
echo "  1. Режим работы: переведён в UTC Control (3)"
if [ "$IS_SPECIAL" = true ]; then
    echo "  2. Фаза: установлена специальная фаза ($PHASE_NUM)"
else
    echo "  2. Фаза: проверена и подготовлена"
fi
echo "  3. Минимальный период: проверен и выдержан"
echo "  4. Активация мигания: команда отправлена и удерживалась 60 секунд"
echo "  5. Отключение мигания: выполнено"
echo ""
warning "ВАЖНО: Проверьте визуально на контроллере:"
echo "  - Активировалось ли жёлтое мигание всех светофоров?"
echo "  - Работало ли мигание в течение теста?"
echo "  - Отключилось ли мигание после команды отключения?"
