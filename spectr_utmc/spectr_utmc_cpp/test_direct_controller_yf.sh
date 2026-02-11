#!/bin/bash
# Прямой тест SET_YF на контроллере через SNMP
# Тестирование без промежуточных компонентов

set -e

CONTROLLER_IP="${1:-192.168.75.150}"
SSH_USER="${2:-voicelink}"
COMMUNITY="${3:-UTMC}"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Прямой тест SET_YF на контроллере                        ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Контроллер: $CONTROLLER_IP"
echo "Пользователь SSH: $SSH_USER"
echo "SNMP Community: $COMMUNITY"
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
    echo -e "${GREEN}✓${NC} $1"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
}

# Функция для выполнения SNMP команды на контроллере через SSH
snmp_on_controller() {
    local cmd="$1"
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$SSH_USER@$CONTROLLER_IP" "$cmd" 2>/dev/null
}

# Функция для получения значения OID
get_oid() {
    local oid="$1"
    local result=$(snmp_on_controller "snmpget -v2c -c $COMMUNITY -Oqv 127.0.0.1 $oid 2>/dev/null" | tail -1 | tr -d '\r\n')
    echo "$result"
}

# Функция для установки значения OID
set_oid() {
    local oid="$1"
    local type="$2"
    local value="$3"
    snmp_on_controller "snmpset -v2c -c $COMMUNITY 127.0.0.1 $oid $type $value 2>&1" > /dev/null
    return $?
}

# ============================================================
# Шаг 1: Проверка доступности контроллера
# ============================================================

log "=== Шаг 1: Проверка доступности контроллера ==="
echo ""

if ping -c 1 -W 2 "$CONTROLLER_IP" > /dev/null 2>&1; then
    success "Контроллер доступен по сети"
else
    error "Контроллер недоступен по сети"
    exit 1
fi

# Проверка SSH доступа
if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$SSH_USER@$CONTROLLER_IP" "echo 'OK'" > /dev/null 2>&1; then
    success "SSH доступ к контроллеру работает"
else
    error "SSH доступ к контроллеру не работает"
    exit 1
fi

# Проверка наличия snmpset
if snmp_on_controller "which snmpset" > /dev/null 2>&1; then
    success "snmpget/snmpset доступны на контроллере"
else
    error "snmpget/snmpset не найдены на контроллере"
    exit 1
fi

echo ""

# ============================================================
# Шаг 2: Проверка текущего состояния контроллера
# ============================================================

log "=== Шаг 2: Проверка текущего состояния контроллера ==="
echo ""

# Режим работы
OPERATION_MODE=$(get_oid "1.3.6.1.4.1.13267.3.2.4.1")
MODE_NAMES=("Local" "Standalone" "Monitor" "UTC Control")
MODE_NAME=${MODE_NAMES[$OPERATION_MODE]:-"Unknown"}
echo "  Режим работы (operationMode): $OPERATION_MODE ($MODE_NAME)"

# Текущая фаза
CURRENT_PHASE=$(get_oid "1.3.6.1.4.1.13267.3.2.5.1.1.3")
echo "  Текущая фаза (utcReplyGn): $CURRENT_PHASE"

# Режим мигания
REPLY_FR=$(get_oid "1.3.6.1.4.1.13267.3.2.5.1.1.36")
if [ "$REPLY_FR" = "1" ]; then
    echo "  Режим мигания (utcReplyFR): $REPLY_FR (АКТИВИРОВАН)"
else
    echo "  Режим мигания (utcReplyFR): $REPLY_FR (не активирован)"
fi

# Контроль мигания
CONTROL_FF=$(get_oid "1.3.6.1.4.1.13267.3.2.4.2.1.20")
if [ "$CONTROL_FF" = "1" ]; then
    echo "  Контроль мигания (utcControlFF): $CONTROL_FF (установлен)"
else
    echo "  Контроль мигания (utcControlFF): $CONTROL_FF (не установлен)"
fi

echo ""

# ============================================================
# Шаг 3: Отправка команды SET_YF
# ============================================================

log "=== Шаг 3: Отправка команды SET_YF ==="
echo ""
warning "⚠️  ВНИМАНИЕ: Будет отправлена команда SET_YF!"
warning "⚠️  Все светофоры на перекрёстке должны мигать жёлтым!"
warning "⚠️  Визуально контролируйте контроллер!"
echo ""
log "Начинаем через 3 секунды..."
sleep 3

# Отправка команды SET_YF (точное копирование Node.js логики)
# Две команды в одной транзакции:
# 1. operationMode = 3 (UTC Control)
# 2. utcControlFF = 1 (включить мигание)

log "Отправка команды SET_YF..."
log "  - operationMode = 3 (UTC Control)"
log "  - utcControlFF = 1 (включить мигание)"
echo ""

if set_oid "1.3.6.1.4.1.13267.3.2.4.1" "i" "3" && \
   set_oid "1.3.6.1.4.1.13267.3.2.4.2.1.20" "i" "1"; then
    success "Команда SET_YF отправлена успешно"
else
    error "Ошибка отправки команды SET_YF"
    exit 1
fi

echo ""
log "Ожидание обработки команды (3 секунды)..."
sleep 3

# ============================================================
# Шаг 4: Проверка результата
# ============================================================

log "=== Шаг 4: Проверка результата ==="
echo ""

# Режим работы
NEW_OPERATION_MODE=$(get_oid "1.3.6.1.4.1.13267.3.2.4.1")
NEW_MODE_NAME=${MODE_NAMES[$NEW_OPERATION_MODE]:-"Unknown"}
echo "  Режим работы (operationMode): $NEW_OPERATION_MODE ($NEW_MODE_NAME)"
if [ "$NEW_OPERATION_MODE" = "3" ]; then
    success "Режим работы установлен в UTC Control (3)"
else
    warning "Режим работы не установлен в UTC Control (текущий: $NEW_OPERATION_MODE)"
fi

# Контроль мигания
NEW_CONTROL_FF=$(get_oid "1.3.6.1.4.1.13267.3.2.4.2.1.20")
echo "  Контроль мигания (utcControlFF): $NEW_CONTROL_FF"
if [ "$NEW_CONTROL_FF" = "1" ]; then
    success "Контроль мигания установлен (utcControlFF=1)"
else
    warning "Контроль мигания не установлен (utcControlFF=$NEW_CONTROL_FF)"
fi

# Режим мигания (ответ контроллера)
NEW_REPLY_FR=$(get_oid "1.3.6.1.4.1.13267.3.2.5.1.1.36")
echo "  Режим мигания (utcReplyFR): $NEW_REPLY_FR"
if [ "$NEW_REPLY_FR" = "1" ]; then
    success "Режим мигания АКТИВИРОВАН (utcReplyFR=1)"
    echo ""
    success "✓✓✓ ЖЁЛТОЕ МИГАНИЕ ДОЛЖНО БЫТЬ АКТИВНО! ✓✓✓"
else
    warning "Режим мигания НЕ активирован (utcReplyFR=$NEW_REPLY_FR)"
    echo ""
    warning "⚠️  Команда отправлена, но контроллер не активировал мигание"
    warning "⚠️  Возможные причины:"
    warning "    - Контроллер не готов принять команду"
    warning "    - Требуется дополнительная последовательность команд"
    warning "    - Контроллер находится в неподходящем состоянии"
fi

echo ""

# ============================================================
# Шаг 5: Сводка результатов
# ============================================================

log "=== Сводка результатов ==="
echo ""
echo "До команды:"
echo "  operationMode: $OPERATION_MODE ($MODE_NAME)"
echo "  utcControlFF: $CONTROL_FF"
echo "  utcReplyFR: $REPLY_FR"
echo ""
echo "После команды:"
echo "  operationMode: $NEW_OPERATION_MODE ($NEW_MODE_NAME)"
echo "  utcControlFF: $NEW_CONTROL_FF"
echo "  utcReplyFR: $NEW_REPLY_FR"
echo ""

if [ "$NEW_OPERATION_MODE" = "3" ] && [ "$NEW_CONTROL_FF" = "1" ] && [ "$NEW_REPLY_FR" = "1" ]; then
    success "✓✓✓ ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ! ✓✓✓"
    echo ""
    success "Команда SET_YF работает корректно!"
    success "Жёлтое мигание должно быть активно на контроллере!"
elif [ "$NEW_OPERATION_MODE" = "3" ] && [ "$NEW_CONTROL_FF" = "1" ] && [ "$NEW_REPLY_FR" != "1" ]; then
    warning "⚠️  Команда отправлена успешно, но контроллер не активировал мигание"
    warning "⚠️  Это базовая версия - используем её как отправную точку"
else
    error "✗ Команда не выполнена полностью"
fi

echo ""
log "=== Тест завершён ==="
echo ""
warning "ВАЖНО: Проверьте визуально на контроллере:"
echo "  - Активировалось ли жёлтое мигание всех светофоров?"
echo "  - Работает ли мигание сейчас?"
echo ""
