#!/bin/bash

# Скрипт для симуляции последовательности команд и проверки состояния контроллера
# Использование: ./test_command_sequence.sh

CONTROLLER_IP="192.168.75.150"
COMMUNITY="UTMC"
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$TEST_DIR/build"

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функция для вывода заголовка
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

# Функция для выполнения GET запроса
get_value() {
    local oid=$1
    local description=$2
    echo -e "${YELLOW}GET: $description${NC}" >&2
    local result=$($BUILD_DIR/test_controller get $CONTROLLER_IP $COMMUNITY $oid 2>&1 | grep "Value:" | sed 's/.*Value: //' | head -1)
    echo "  Результат: $result" >&2
    echo "$result"
}

# Функция для выполнения SET запроса
set_value() {
    local oid=$1
    local type=$2
    local value=$3
    local description=$4
    echo -e "${YELLOW}SET: $description${NC}"
    $BUILD_DIR/test_controller set $CONTROLLER_IP $COMMUNITY $oid $type "$value" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}✅ Успешно${NC}"
        return 0
    else
        echo -e "  ${RED}❌ Ошибка${NC}"
        return 1
    fi
}

# Функция для выполнения множественного SET
set_multiple() {
    local description=$1
    shift
    echo -e "${YELLOW}SET (multiple): $description${NC}"
    $BUILD_DIR/test_controller setmulti $CONTROLLER_IP $COMMUNITY "$@" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}✅ Успешно${NC}"
        return 0
    else
        echo -e "  ${RED}❌ Ошибка${NC}"
        return 1
    fi
}

# Функция для ожидания
wait_seconds() {
    local seconds=$1
    echo -e "${YELLOW}⏳ Ожидание $seconds секунд...${NC}"
    sleep $seconds
}

# Функция для получения текущего состояния
get_current_state() {
    print_header "Текущее состояние контроллера"
    
    local mode=$(get_value "1.3.6.1.4.1.13267.3.2.4.1" "Operation Mode")
    local phase=$(get_value "1.3.6.1.4.1.13267.3.2.5.1.1.3" "Current Phase")
    local af=$(get_value "1.3.6.1.4.1.13267.3.2.5.1.1.36" "ЖМ (желтое мигание)")
    local error=$(get_value "1.3.6.1.4.1.13267.3.2.5.1.1.5" "Errors")
    local warnings=$(get_value "1.3.6.1.4.1.13267.3.2.5.1.1.16" "Warnings")
    
    echo ""
    echo "Состояние:"
    echo "  Operation Mode: $mode"
    echo "  Current Phase: $phase"
    echo "  ЖМ: $af"
    echo "  Errors: $error"
    echo "  Warnings: $warnings"
    echo ""
}

# Проверка наличия test_controller
if [ ! -f "$BUILD_DIR/test_controller" ]; then
    echo -e "${RED}Ошибка: test_controller не найден в $BUILD_DIR${NC}"
    echo "Сначала соберите проект: cd build && cmake .. && make"
    exit 1
fi

print_header "Симуляция последовательности команд на контроллере"
echo "Контроллер: $CONTROLLER_IP"
echo "Community: $COMMUNITY"
echo ""

# Шаг 1: Получение исходного состояния
get_current_state

# Шаг 2: Перевод в режим UTC Control
print_header "Шаг 1: Перевод в режим UTC Control"
set_value "1.3.6.1.4.1.13267.3.2.4.1" "2" "3" "Operation Mode -> UTC Control (3)"
wait_seconds 2
get_current_state

# Шаг 3: Установка фазы 1
print_header "Шаг 2: Установка фазы 1"
set_multiple "Установка режима UTC Control и фазы 1" \
    "1.3.6.1.4.1.13267.3.2.4.1" "2" "3" \
    "1.3.6.1.4.1.13267.3.2.4.2.1.5" "4" "$(printf '\x01')"
wait_seconds 3
get_current_state

# Шаг 4: Установка фазы 2
print_header "Шаг 3: Установка фазы 2"
set_value "1.3.6.1.4.1.13267.3.2.4.2.1.5" "4" "$(printf '\x02')" "Phase -> 2"
wait_seconds 3
get_current_state

# Шаг 5: Установка фазы 3
print_header "Шаг 4: Установка фазы 3"
set_value "1.3.6.1.4.1.13267.3.2.4.2.1.5" "4" "$(printf '\x04')" "Phase -> 3"
wait_seconds 3
get_current_state

# Шаг 6: Попытка включения ЖМ
print_header "Шаг 5: Попытка включения ЖМ"
set_multiple "Установка режима UTC Control и FF=1 для ЖМ" \
    "1.3.6.1.4.1.13267.3.2.4.1" "2" "3" \
    "1.3.6.1.4.1.13267.3.2.4.2.1.20" "2" "1"
echo "Удерживаем FF=1 в течение 12 секунд..."
for i in {1..6}; do
    echo "  Проверка $i/6..."
    set_value "1.3.6.1.4.1.13267.3.2.4.2.1.20" "2" "1" "FF=1 (удержание)" > /dev/null 2>&1
    sleep 2
done
wait_seconds 5
get_current_state

# Шаг 7: Возврат в локальный режим
print_header "Шаг 6: Возврат в локальный режим (Standalone)"
set_multiple "Выключение FF и LO, возврат в Standalone" \
    "1.3.6.1.4.1.13267.3.2.4.2.1.11" "2" "0" \
    "1.3.6.1.4.1.13267.3.2.4.2.1.20" "2" "0" \
    "1.3.6.1.4.1.13267.3.2.4.1" "2" "1"
wait_seconds 3
get_current_state

# Финальное состояние
print_header "Финальное состояние контроллера"
get_current_state

print_header "Тестирование завершено"
echo -e "${GREEN}Все команды выполнены. Проверьте результаты выше.${NC}"
