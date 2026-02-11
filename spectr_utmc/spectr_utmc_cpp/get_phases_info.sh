#!/bin/bash

# Скрипт для получения информации о фазах контроллера

CONTROLLER_IP="192.168.75.150"
COMMUNITY="UTMC"
TEST_BIN="./build/test_controller"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Информация о фазах контроллера                           ║${NC}"
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
    # Убираем пробелы и префикс "Hex-STRING:"
    hex=$(echo "$hex" | sed 's/Hex-STRING: //' | tr -d ' ')
    
    # Берем первый байт
    local first_byte=$(echo "$hex" | cut -d' ' -f1)
    
    if [ -z "$first_byte" ] || [ "$first_byte" = "00" ]; then
        echo "0"
        return
    fi
    
    # Конвертируем hex в десятичное
    local decimal=$((16#${first_byte}))
    
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

echo -e "${YELLOW}=== Текущее состояние ===${NC}"
echo ""

# Текущая фаза
echo -n "Текущая фаза (Gn): "
PHASE_HEX=$(get_oid "1.3.6.1.4.1.13267.3.2.5.1.1.3")
CURRENT_PHASE=$(hex_to_phase "$PHASE_HEX")
if [ "$CURRENT_PHASE" != "0" ]; then
    echo -e "${GREEN}Фаза $CURRENT_PHASE${NC} (hex: $PHASE_HEX)"
else
    echo "Не определена (hex: $PHASE_HEX)"
fi

# Счётчик фазы
echo -n "Счётчик текущей фазы: "
STAGE_COUNTER=$(get_oid "1.3.6.1.4.1.13267.3.2.5.1.1.5" | grep -oE "[0-9]+" | head -1)
echo "$STAGE_COUNTER"

echo ""
echo -e "${YELLOW}=== Попытка чтения конфигурации фаз ===${NC}"
echo ""

# Попробуем прочитать информацию о фазах через различные OID
# Возможно, есть таблица фаз или конфигурация

echo "Попытка 1: Чтение через GET_CONFIG команду..."
echo "  (Требуется реализация команды GET_CONFIG)"
echo ""

echo "Попытка 2: Поиск OID для конфигурации фаз..."
echo "  Проверяем различные OID..."

# Попробуем прочитать возможные OID для конфигурации фаз
for i in {1..7}; do
    # Возможные OID для длительности фаз
    oid1="1.3.6.1.4.1.13267.3.2.4.2.1.$i"
    oid2="1.3.6.1.4.1.13267.3.2.5.1.1.$((10+i))"
    
    echo -n "  Фаза $i: "
    result1=$(get_oid "$oid1" 2>&1 | grep -v "No Such Object" | grep -v "ERROR" | head -1)
    result2=$(get_oid "$oid2" 2>&1 | grep -v "No Such Object" | grep -v "ERROR" | head -1)
    
    if [ -n "$result1" ] && [ "$result1" != "No Such Object" ]; then
        echo -e "${GREEN}OID $oid1: $result1${NC}"
    elif [ -n "$result2" ] && [ "$result2" != "No Such Object" ]; then
        echo -e "${GREEN}OID $oid2: $result2${NC}"
    else
        echo "не найдено"
    fi
done

echo ""
echo -e "${YELLOW}=== Примечание ===${NC}"
echo "Для получения полной информации о конфигурации фаз может потребоваться:"
echo "  1. Использование команды GET_CONFIG через протокол Spectr-ITS"
echo "  2. Чтение конфигурационного файла контроллера (если доступен)"
echo "  3. Использование SNMP walk для поиска таблицы фаз"
echo ""
echo "Текущая информация показывает только активную фазу в данный момент."
