#!/bin/bash

# Пошаговое тестирование передачи SCN
# Шаг за шагом, с подтверждением на каждом этапе

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Конфигурация
CONTROLLER_IP="192.168.75.150"
COMMUNITY="UTMC"
SCN="CO11111"

# Функции для вывода
print_header() {
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Функция для формирования OID с SCN
build_oid_with_scn() {
    local base_oid=$1
    local scn=$2
    local oid="${base_oid}.1"  # timestamp = 1 (NOW)
    
    # Добавляем ASCII коды символов SCN
    for (( i=0; i<${#scn}; i++ )); do
        char="${scn:$i:1}"
        ascii_code=$(printf "%d" "'$char")
        oid="${oid}.${ascii_code}"
    done
    
    echo "$oid"
}

# Функция для выполнения GET запроса
get_value() {
    local oid=$1
    local description=$2
    
    echo -e "${CYAN}GET: $description${NC}"
    echo "  OID: $oid"
    
    local result=$(./build/test_controller get "$CONTROLLER_IP" "$COMMUNITY" "$oid" 2>&1)
    echo "  Результат: $result"
    
    if echo "$result" | grep -q "ERROR"; then
        print_error "GET запрос не удался"
        return 1
    else
        print_success "GET запрос выполнен"
        return 0
    fi
}

# Функция для выполнения SET запроса
set_value() {
    local oid=$1
    local type=$2
    local value=$3
    local description=$4
    
    echo -e "${CYAN}SET: $description${NC}"
    echo "  OID: $oid"
    echo "  Type: $type"
    echo "  Value: $value"
    
    local result=$(./build/test_controller set "$CONTROLLER_IP" "$COMMUNITY" "$oid" "$type" "$value" 2>&1)
    echo "  Результат: $result"
    
    if echo "$result" | grep -q "ERROR"; then
        print_error "SET запрос не удался"
        return 1
    else
        print_success "SET запрос выполнен"
        return 0
    fi
}

# Проверка наличия test_controller
if [ ! -f "./build/test_controller" ]; then
    print_error "test_controller не найден. Сначала соберите проект: cd build && make"
    exit 1
fi

print_header "ПОШАГОВОЕ ТЕСТИРОВАНИЕ ПЕРЕДАЧИ SCN"
print_info "Контроллер: $CONTROLLER_IP"
print_info "SCN: $SCN"
print_info "Community: $COMMUNITY"

# ============================================================================
# ШАГ 1: Проверка формирования OID с SCN
# ============================================================================
print_header "ШАГ 1: Проверка формирования OID с SCN"

print_info "Проверяем функцию buildOIDWithSCN..."

# Примеры OID
BASE_OID_PHASE="1.3.6.1.4.1.13267.3.2.4.2.1.5"
BASE_OID_AF="1.3.6.1.4.1.13267.3.2.4.2.1.20"
BASE_OID_GET_PHASE="1.3.6.1.4.1.13267.3.2.5.1.1.3"
BASE_OID_GET_AF="1.3.6.1.4.1.13267.3.2.5.1.1.36"

OID_PHASE=$(build_oid_with_scn "$BASE_OID_PHASE" "$SCN")
OID_AF=$(build_oid_with_scn "$BASE_OID_AF" "$SCN")
OID_GET_PHASE=$(build_oid_with_scn "$BASE_OID_GET_PHASE" "$SCN")
OID_GET_AF=$(build_oid_with_scn "$BASE_OID_GET_AF" "$SCN")

echo "SetPhase OID: $OID_PHASE"
echo "SetAF OID: $OID_AF"
echo "GetPhase OID: $OID_GET_PHASE"
echo "GetAF OID: $OID_GET_AF"

# Проверка формата
EXPECTED_SUFFIX=".1.67.79.49.49.49.49.49"  # .1.C.O.1.1.1.1.1
if [[ "$OID_PHASE" == *"$EXPECTED_SUFFIX" ]]; then
    print_success "Формат OID правильный"
else
    print_error "Формат OID неправильный! Ожидалось окончание: $EXPECTED_SUFFIX"
    exit 1
fi

echo ""
read -p "Продолжить к следующему шагу? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi

# ============================================================================
# ШАГ 2: Тестирование GET операций БЕЗ SCN (базовые OID)
# ============================================================================
print_header "ШАГ 2: Тестирование GET операций БЕЗ SCN (для сравнения)"

print_info "Проверяем базовые GET операции без SCN..."

# GetTime (не требует SCN)
get_value "1.3.6.1.4.1.13267.3.2.3.2.0" "GetTime (без SCN)"

# Operation Mode (не требует SCN)
get_value "1.3.6.1.4.1.13267.3.2.4.1.0" "Operation Mode (без SCN)"

echo ""
read -p "Продолжить к следующему шагу? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi

# ============================================================================
# ШАГ 3: Тестирование GET операций С SCN
# ============================================================================
print_header "ШАГ 3: Тестирование GET операций С SCN"

print_info "Проверяем GET операции с SCN..."
print_warning "Если запросы не удаются, возможно формат SCN неправильный"

# GetPhase с SCN
get_value "$OID_GET_PHASE" "GetPhase (с SCN)"

# GetAF с SCN
get_value "$OID_GET_AF" "GetAF (с SCN)"

echo ""
read -p "Продолжить к следующему шагу? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi

# ============================================================================
# ШАГ 4: Тестирование SET Operation Mode (без SCN)
# ============================================================================
print_header "ШАГ 4: Тестирование SET Operation Mode (без SCN)"

print_info "Устанавливаем режим UTC Control (3)..."
print_warning "Это безопасная операция, не изменяет фазу или ЖМ"

set_value "1.3.6.1.4.1.13267.3.2.4.1.0" "2" "3" "Operation Mode = UTC Control (3)"

# Проверяем результат
sleep 1
get_value "1.3.6.1.4.1.13267.3.2.4.1.0" "Проверка Operation Mode"

echo ""
read -p "Продолжить к следующему шагу? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi

# ============================================================================
# ШАГ 5: Тестирование SET Phase С SCN
# ============================================================================
print_header "ШАГ 5: Тестирование SET Phase С SCN"

print_info "Устанавливаем фазу 1 с использованием OID с SCN..."
print_warning "Это изменит текущую фазу контроллера!"

# Bit mask для фазы 1: 2**(1-1) = 2**0 = 1 = 0x01
PHASE_VALUE=$(printf '\x01')

set_value "$OID_PHASE" "4" "$PHASE_VALUE" "SetPhase = 1 (с SCN)"

# Проверяем результат
sleep 2
get_value "$OID_GET_PHASE" "Проверка текущей фазы (с SCN)"

echo ""
read -p "Продолжить к следующему шагу? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi

# ============================================================================
# ШАГ 6: Тестирование SET AF (желтое мигание) С SCN
# ============================================================================
print_header "ШАГ 6: Тестирование SET AF (желтое мигание) С SCN"

print_info "Устанавливаем FF=1 для включения желтого мигания..."
print_warning "Согласно документации, FF=1 должен удерживаться минимум 10 секунд"
print_warning "Пожалуйста, визуально контролируйте светофор!"

# Сначала устанавливаем режим UTC Control
set_value "1.3.6.1.4.1.13267.3.2.4.1.0" "2" "3" "Operation Mode = UTC Control (3)"

sleep 1

# Устанавливаем FF=1 с SCN
set_value "$OID_AF" "2" "1" "SetAF = 1 (желтое мигание, с SCN)"

print_info "Удерживаем FF=1 в течение 15 секунд (минимум 10 секунд по документации)..."
for i in {1..8}; do
    echo "  Удержание $i/8 (через $((i*2)) секунд)..."
    set_value "$OID_AF" "2" "1" "Удержание FF=1" > /dev/null 2>&1
    sleep 2
done

# Проверяем результат
sleep 2
get_value "$OID_GET_AF" "Проверка состояния ЖМ (с SCN)"

print_info "Пожалуйста, визуально проверьте светофор - должно быть желтое мигание!"

echo ""
read -p "Визуально видно желтое мигание? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_success "Желтое мигание включено! Тест успешен!"
else
    print_warning "Желтое мигание не видно. Возможно, нужны дополнительные условия."
fi

echo ""
read -p "Продолжить к следующему шагу? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi

# ============================================================================
# ШАГ 7: Возврат в локальный режим
# ============================================================================
print_header "ШАГ 7: Возврат в локальный режим"

print_info "Возвращаем контроллер в локальный режим..."

# Выключаем FF
set_value "$OID_AF" "2" "0" "SetAF = 0 (выключить ЖМ)"

sleep 1

# Возвращаем в локальный режим
set_value "1.3.6.1.4.1.13267.3.2.4.1.0" "2" "1" "Operation Mode = Standalone (1)"

print_success "Тестирование завершено!"
