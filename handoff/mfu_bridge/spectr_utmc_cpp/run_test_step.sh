#!/bin/bash

# Скрипт для выполнения одного шага тестирования
# Использование: ./run_test_step.sh <номер_шага>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
TEST_BIN="${BUILD_DIR}/test_controller"
CONTROLLER_IP="192.168.75.150"

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Запуск шагов тестирования (Spectr UTMC) ===${NC}"
echo ""

# Проверка наличия бинарника
if [ ! -f "$TEST_BIN" ]; then
    echo -e "${RED}Ошибка: test_controller не найден${NC}"
    echo "Сборка проекта..."
    mkdir -p "$BUILD_DIR" && cd "$BUILD_DIR" && cmake .. && make
    if [ $? -ne 0 ]; then
        echo -e "${RED}Сборка не удалась!${NC}"
        exit 1
    fi
    cd "$SCRIPT_DIR"
fi

case "$1" in
    "0.1"|"prep1")
        echo -e "${YELLOW}Шаг 0.1: Проверка доступности контроллера${NC}"
        echo ""
        ping -c 4 "$CONTROLLER_IP"
        ;;
        
    "0.2"|"prep2")
        echo -e "${YELLOW}Шаг 0.2: Проверка портов${NC}"
        echo ""
        echo "Проверка SSH (22)..."
        nc -zv -w 3 "$CONTROLLER_IP" 22
        echo ""
        echo "Проверка HTTPS (443)..."
        nc -zv -w 3 "$CONTROLLER_IP" 443
        echo ""
        echo "Проверка SNMP (161/UDP)..."
        nc -zv -w 3 -u "$CONTROLLER_IP" 161
        ;;
        
    "1.1"|"community")
        echo -e "${YELLOW}Шаг 1.1: Проверка community${NC}"
        echo ""
        read -p "Введите community для проверки [UTMC]: " community
        community=${community:-UTMC}
        echo ""
        echo -e "${GREEN}Проверка с community: $community${NC}"
        "$TEST_BIN" connect "$CONTROLLER_IP" "$community"
        ;;
        
    "2.1"|"sysuptime")
        echo -e "${YELLOW}Шаг 2.1: Проверка sysUpTime${NC}"
        echo ""
        read -p "Введите community [UTMC]: " community
        community=${community:-UTMC}
        echo ""
        "$TEST_BIN" connect "$CONTROLLER_IP" "$community" | grep -A 5 "sysUpTime"
        ;;
        
    "4.1"|"traps")
        echo -e "${YELLOW}Шаг 4.1: Проверка приемника trap'ов${NC}"
        echo ""
        read -p "Введите порт trap'ов [10162]: " port
        port=${port:-10162}
        read -p "Введите community [UTMC]: " community
        community=${community:-UTMC}
        echo ""
        echo -e "${GREEN}Запуск приемника trap'ов на порту $port...${NC}"
        echo "Нажмите Ctrl+C для остановки"
        "$TEST_BIN" traps "$port" "$community"
        ;;
        
    "full")
        echo -e "${YELLOW}Запуск полного теста связности${NC}"
        echo ""
        read -p "Введите community [UTMC]: " community
        community=${community:-UTMC}
        echo ""
        "$TEST_BIN" connect "$CONTROLLER_IP" "$community"
        ;;
        
    *)
        echo "Использование: $0 <номер_шага>"
        echo ""
        echo "Доступные шаги:"
        echo "  0.1, prep1     - Проверка доступности контроллера (ping)"
        echo "  0.2, prep2     - Проверка портов (SSH, HTTPS, SNMP)"
        echo "  1.1, community - Проверка community"
        echo "  2.1, sysuptime - Проверка SNMP GET sysUpTime"
        echo "  4.1, traps     - Проверка приемника trap'ов"
        echo "  full           - Полный тест связности"
        echo ""
        echo "Пример: $0 1.1"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}Шаг выполнен${NC}"
