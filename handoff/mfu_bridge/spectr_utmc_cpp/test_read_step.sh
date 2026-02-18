#!/bin/bash

# Скрипт для пошагового тестирования чтения данных с контроллера
# Использование: ./test_read_step.sh <step_number>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
TEST_BIN="${BUILD_DIR}/test_controller"
CONTROLLER_IP="192.168.75.150"
COMMUNITY="UTMC"

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Пошаговый тест чтения (Spectr UTMC) ===${NC}"
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
    "1.1"|"ping")
        echo -e "${YELLOW}Шаг 1.1: Проверка доступности контроллера${NC}"
        echo ""
        ping -c 2 "$CONTROLLER_IP"
        echo ""
        echo -e "${GREEN}Шаг выполнен. Проверьте результаты выше.${NC}"
        ;;
        
    "1.2"|"port")
        echo -e "${YELLOW}Шаг 1.2: Проверка SNMP порта${NC}"
        echo ""
        echo "Проверка UDP порта 161..."
        nc -zv -u -w 3 "$CONTROLLER_IP" 161
        echo ""
        echo -e "${GREEN}Шаг выполнен. Проверьте результаты выше.${NC}"
        ;;
        
    "2.1"|"session")
        echo -e "${YELLOW}Шаг 2.1: Создание SNMP-сессии${NC}"
        echo ""
        read -p "Введите community [UTMC]: " community
        community=${community:-UTMC}
        echo ""
        echo -e "${GREEN}Проверка создания сессии с community: $community${NC}"
        echo ""
        "$TEST_BIN" connect "$CONTROLLER_IP" "$community" 2>&1 | head -20
        echo ""
        echo -e "${GREEN}Шаг выполнен. Проверьте, что выше есть 'Session created successfully'.${NC}"
        ;;
        
    "3.1"|"sysuptime")
        echo -e "${YELLOW}Шаг 3.1: Чтение sysUpTime${NC}"
        echo ""
        read -p "Введите community [UTMC]: " community
        community=${community:-UTMC}
        echo ""
        echo -e "${GREEN}Чтение sysUpTime с $CONTROLLER_IP...${NC}"
        echo ""
        "$TEST_BIN" connect "$CONTROLLER_IP" "$community" 2>&1 | grep -A 10 "sysUpTime"
        echo ""
        echo -e "${GREEN}Шаг выполнен. Проверьте результаты выше.${NC}"
        ;;
        
    "4.1"|"version")
        echo -e "${YELLOW}Шаг 4.1: Чтение версии приложения${NC}"
        echo ""
        read -p "Введите community [UTMC]: " community
        community=${community:-UTMC}
        echo ""
        echo -e "${GREEN}Чтение версии приложения с $CONTROLLER_IP...${NC}"
        echo ""
        "$TEST_BIN" connect "$CONTROLLER_IP" "$community" 2>&1 | grep -Ei -A 10 "Application Version|версия"
        echo ""
        echo -e "${GREEN}Шаг выполнен. Проверьте результаты выше.${NC}"
        ;;
        
    "4.3"|"mode")
        echo -e "${YELLOW}Шаг 4.3: Чтение operationMode${NC}"
        echo ""
        read -p "Введите community [UTMC]: " community
        community=${community:-UTMC}
        echo ""
        echo -e "${GREEN}Чтение operationMode с $CONTROLLER_IP...${NC}"
        echo ""
        "$TEST_BIN" connect "$CONTROLLER_IP" "$community" 2>&1 | grep -Ei -A 15 "Operation Mode|operationMode|Режим"
        echo ""
        echo -e "${GREEN}Шаг выполнен. Проверьте результаты выше.${NC}"
        ;;
        
    "4.5"|"time")
        echo -e "${YELLOW}Шаг 4.5: Чтение времени контроллера${NC}"
        echo ""
        read -p "Введите community [UTMC]: " community
        community=${community:-UTMC}
        echo ""
        echo -e "${GREEN}Чтение времени контроллера с $CONTROLLER_IP...${NC}"
        echo ""
        "$TEST_BIN" connect "$CONTROLLER_IP" "$community" 2>&1 | grep -Ei -A 10 "Controller Time|время"
        echo ""
        echo -e "${GREEN}Шаг выполнен. Проверьте результаты выше.${NC}"
        ;;
        
    "5.1"|"phase")
        echo -e "${YELLOW}Шаг 5.1: Чтение текущей фазы${NC}"
        echo ""
        echo -e "${YELLOW}Примечание: для этого OID может потребоваться параметр SCN${NC}"
        read -p "Введите community [UTMC]: " community
        community=${community:-UTMC}
        echo ""
        echo -e "${GREEN}Чтение текущей фазы с $CONTROLLER_IP...${NC}"
        echo ""
        "$TEST_BIN" connect "$CONTROLLER_IP" "$community" 2>&1 | grep -A 10 "phase\|Phase\|GN"
        echo ""
        echo -e "${GREEN}Шаг выполнен. Проверьте результаты выше.${NC}"
        ;;
        
    "full"|"all")
        echo -e "${YELLOW}Запуск полного теста чтения${NC}"
        echo ""
        read -p "Введите community [UTMC]: " community
        community=${community:-UTMC}
        echo ""
        echo -e "${GREEN}Запуск полного теста связности...${NC}"
        echo ""
        "$TEST_BIN" connect "$CONTROLLER_IP" "$community"
        echo ""
        echo -e "${GREEN}Полный тест завершен.${NC}"
        ;;
        
    *)
        echo "Использование: $0 <номер_шага>"
        echo ""
        echo "Доступные шаги:"
        echo "  1.1, ping      - Проверка доступности контроллера"
        echo "  1.2, port      - Проверка SNMP порта"
        echo "  2.1, session   - Создание SNMP сессии"
        echo "  3.1, sysuptime - Чтение sysUpTime"
        echo "  4.1, version   - Чтение версии приложения"
        echo "  4.3, mode      - Чтение режима работы (operationMode)"
        echo "  4.5, time      - Чтение времени контроллера"
        echo "  5.1, phase     - Чтение текущей фазы"
        echo "  full, all      - Полный тест чтения"
        echo ""
        echo "Пример: $0 2.1"
        exit 1
        ;;
esac

echo ""
echo -e "${BLUE}=== Шаг выполнен ===${NC}"
echo "Review results above and update TEST_READ_PLAN.md"
