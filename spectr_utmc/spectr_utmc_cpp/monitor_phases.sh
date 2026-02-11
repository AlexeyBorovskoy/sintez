#!/bin/bash

# Скрипт для мониторинга фаз контроллера и определения их количества и продолжительности

CONTROLLER_IP="192.168.75.150"
COMMUNITY="UTMC"
TEST_BIN="./build/test_controller"
MONITOR_TIME=300  # Мониторинг в течение 5 минут

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Мониторинг фаз контроллера                              ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Функция для чтения OID
get_oid() {
    local oid=$1
    local result=$($TEST_BIN get "$CONTROLLER_IP" "$COMMUNITY" "$oid" 2>&1 | grep "Value:" | sed 's/.*Value: //')
    echo "$result"
}

# Функция для преобразования hex в номер фазы
hex_to_phase() {
    local hex=$1
    # Убираем "Hex-STRING: " и берем первый байт
    hex=$(echo "$hex" | sed 's/Hex-STRING: //' | awk '{print $1}')
    
    if [ -z "$hex" ] || [ "$hex" = "00" ]; then
        echo "0"
        return
    fi
    
    # Конвертируем hex в десятичное
    local decimal=$((16#${hex}))
    
    # Определяем номер фазы из битовой маски
    for i in {0..7}; do
        local bit=$((decimal & (1 << i)))
        if [ $bit -ne 0 ]; then
            echo $((i + 1))
            return
        fi
    done
    
    echo "0"
}

# Чтение текущей информации
echo -e "${YELLOW}=== Текущее состояние ===${NC}"
echo ""

PHASE_HEX=$(get_oid "1.3.6.1.4.1.13267.3.2.5.1.1.3")
CURRENT_PHASE=$(hex_to_phase "$PHASE_HEX")

echo "Текущая фаза: ${GREEN}Фаза $CURRENT_PHASE${NC} (hex: $PHASE_HEX)"
echo ""

# Попытка прочитать длительность через другие OID
echo -e "${YELLOW}=== Поиск информации о продолжительности фаз ===${NC}"
echo ""

# Проверяем различные возможные OID для длительности
for i in {10..30}; do
    oid="1.3.6.1.4.1.13267.3.2.5.1.1.$i"
    result=$(get_oid "$oid" 2>&1 | grep -v "No Such Object" | grep -v "ERROR" | head -1)
    if [ -n "$result" ] && [ "$result" != "No Such Object" ] && [ -n "$(echo "$result" | grep -E "[0-9]+")" ]; then
        echo "OID $oid: $result"
    fi
done

echo ""
echo -e "${YELLOW}=== Результат ===${NC}"
echo ""
echo "Текущая активная фаза: ${GREEN}Фаза $CURRENT_PHASE${NC}"
echo ""
echo -e "${RED}Примечание:${NC} Для определения количества фаз и их продолжительности"
echo "необходимо мониторить контроллер в течение полного цикла."
echo "Контроллер может иметь от 2 до 7 фаз в зависимости от конфигурации."
echo ""
echo "Для получения полной информации рекомендуется:"
echo "  1. Мониторить контроллер в течение нескольких циклов"
echo "  2. Использовать SNMP traps для отслеживания смены фаз"
echo "  3. Проверить конфигурационный файл контроллера (если доступен)"
