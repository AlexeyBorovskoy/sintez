#!/bin/bash

# Скрипт для тестирования с визуальным подтверждением
# Цель: Установить фазу на длительное время и включить желтое мигание для визуальной проверки

CONTROLLER_IP="192.168.75.150"
COMMUNITY="UTMC"
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$TEST_DIR/build"

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header() {
    echo -e "\n${BLUE}════════════════════════════════════════${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}\n"
}

print_info() {
    echo -e "${CYAN}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Функция для получения значения
get_value() {
    local oid=$1
    $BUILD_DIR/test_controller get $CONTROLLER_IP $COMMUNITY $oid 2>&1 | grep "Value:" | sed 's/.*Value: //' | head -1
}

# Функция для установки значения
set_value() {
    local oid=$1
    local type=$2
    local value=$3
    $BUILD_DIR/test_controller set $CONTROLLER_IP $COMMUNITY $oid $type "$value" > /dev/null 2>&1
    return $?
}

# Функция для множественного SET
set_multiple() {
    $BUILD_DIR/test_controller setmulti $CONTROLLER_IP $COMMUNITY "$@" > /dev/null 2>&1
    return $?
}

print_header "ТЕСТ С ВИЗУАЛЬНЫМ ПОДТВЕРЖДЕНИЕМ"
echo "Контроллер: $CONTROLLER_IP"
echo "Цель: Установить фазу на длительное время и попытаться включить ЖМ"
echo ""

# Шаг 1: Проверка текущего состояния
print_header "ШАГ 1: Проверка текущего состояния контроллера"

print_info "Получаем текущее состояние..."
MODE=$(get_value "1.3.6.1.4.1.13267.3.2.4.1")
PHASE=$(get_value "1.3.6.1.4.1.13267.3.2.5.1.1.3")
AF=$(get_value "1.3.6.1.4.1.13267.3.2.5.1.1.36")

echo "  Operation Mode: $MODE"
echo "  Current Phase: $PHASE"
echo "  ЖМ: $AF"
echo ""

# Шаг 2: Перевод в режим UTC Control
print_header "ШАГ 2: Перевод контроллера в режим UTC Control"

print_info "Устанавливаем Operation Mode = 3 (UTC Control)..."
if set_value "1.3.6.1.4.1.13267.3.2.4.1" "2" "3"; then
    print_success "Operation Mode установлен в UTC Control"
    sleep 2
    
    # Проверка
    NEW_MODE=$(get_value "1.3.6.1.4.1.13267.3.2.4.1")
    echo "  Проверка: Operation Mode = $NEW_MODE"
    if [[ "$NEW_MODE" == *"3"* ]]; then
        print_success "Режим UTC Control подтвержден!"
    else
        print_warning "Режим не изменился или изменился неожиданно"
    fi
else
    print_error "Не удалось установить режим UTC Control"
    exit 1
fi

# Шаг 3: Установка фазы 1 на длительное время
print_header "ШАГ 3: Установка фазы 1 для визуального подтверждения"

print_info "Устанавливаем фазу 1 (битовая маска 0x01)..."
print_warning "ВНИМАНИЕ: Это изменит текущую фазу светофора!"
echo ""
echo -e "${YELLOW}Пожалуйста, визуально проверьте светофор - должна быть активна фаза 1${NC}"
echo ""

if set_multiple \
    "1.3.6.1.4.1.13267.3.2.4.1" "2" "3" \
    "1.3.6.1.4.1.13267.3.2.4.2.1.5" "4" "$(printf '\x01')"; then
    print_success "Фаза 1 установлена"
    sleep 3
    
    # Проверка фазы
    NEW_PHASE=$(get_value "1.3.6.1.4.1.13267.3.2.5.1.1.3")
    echo "  Проверка: Current Phase = $NEW_PHASE"
    echo ""
    print_info "⏳ Ожидание 5 секунд для визуального подтверждения..."
    echo -e "${CYAN}Пожалуйста, визуально проверьте светофор - должна быть активна фаза 1${NC}"
    sleep 5
    
    # Повторная проверка
    NEW_PHASE2=$(get_value "1.3.6.1.4.1.13267.3.2.5.1.1.3")
    echo "  Повторная проверка: Current Phase = $NEW_PHASE2"
    echo ""
    echo -e "${GREEN}✓ Если фаза 1 визуально активна на светофоре - тест успешен!${NC}"
else
    print_error "Не удалось установить фазу 1"
fi

# Шаг 4: Попытка включения желтого мигания
print_header "ШАГ 4: Попытка включения желтого мигания"

print_info "Устанавливаем FF=1 для включения ЖМ..."
print_warning "Согласно документации, FF=1 должен удерживаться минимум 10 секунд"
echo ""

if set_multiple \
    "1.3.6.1.4.1.13267.3.2.4.1" "2" "3" \
    "1.3.6.1.4.1.13267.3.2.4.2.1.20" "2" "1"; then
    print_success "FF=1 установлен"
    echo ""
    print_info "Удерживаем FF=1 в течение 15 секунд (минимум 10 секунд по документации)..."
    echo -e "${CYAN}Пожалуйста, визуально проверьте светофор - должно быть желтое мигание${NC}"
    
    # Удерживаем FF=1
    for i in {1..8}; do
        echo "  Удержание $i/8 (через $((i*2)) секунд)..."
        set_value "1.3.6.1.4.1.13267.3.2.4.2.1.20" "2" "1" > /dev/null 2>&1
        sleep 2
    done
    
    echo ""
    print_info "Ожидание еще 5 секунд для завершения минимальных периодов работы фаз..."
    sleep 5
    
    # Проверка ЖМ
    NEW_AF=$(get_value "1.3.6.1.4.1.13267.3.2.5.1.1.36")
    echo "  Проверка: GetAF (ЖМ) = $NEW_AF"
    echo ""
    
    if [[ "$NEW_AF" == *"1"* ]]; then
        print_success "ЖМ включено (GetAF = 1)!"
        echo -e "${GREEN}✓ Если желтое мигание визуально активно - тест успешен!${NC}"
    else
        print_warning "GetAF показывает 0 (ЖМ не включено)"
        echo -e "${YELLOW}⚠️  Возможно, требуется передача SCN или другие условия${NC}"
        echo -e "${YELLOW}⚠️  Проверьте визуально - возможно, ЖМ включилось, но GetAF не обновился${NC}"
    fi
else
    print_error "Не удалось установить FF=1"
fi

# Шаг 5: Возврат в нормальный режим
print_header "ШАГ 5: Возврат контроллера в нормальный режим"

print_info "Выключаем ЖМ и возвращаем в Standalone режим..."
if set_multiple \
    "1.3.6.1.4.1.13267.3.2.4.2.1.20" "2" "0" \
    "1.3.6.1.4.1.13267.3.2.4.2.1.11" "2" "0" \
    "1.3.6.1.4.1.13267.3.2.4.1" "2" "1"; then
    print_success "Контроллер возвращен в Standalone режим"
    sleep 2
    
    FINAL_MODE=$(get_value "1.3.6.1.4.1.13267.3.2.4.1")
    FINAL_AF=$(get_value "1.3.6.1.4.1.13267.3.2.5.1.1.36")
    echo "  Финальное состояние:"
    echo "    Operation Mode: $FINAL_MODE"
    echo "    ЖМ: $FINAL_AF"
else
    print_error "Не удалось вернуть контроллер в нормальный режим"
fi

print_header "ТЕСТИРОВАНИЕ ЗАВЕРШЕНО"
echo ""
echo -e "${CYAN}Пожалуйста, сообщите результаты визуальной проверки:${NC}"
echo "  1. Была ли активна фаза 1 на светофоре?"
echo "  2. Включилось ли желтое мигание?"
echo "  3. Сколько времени потребовалось для переключения?"
echo ""
