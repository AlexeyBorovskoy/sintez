#!/bin/bash

# Простой скрипт для тестирования SNMP подключения используя стандартные утилиты
# Использование: ./test_snmp_simple.sh <step>

CONTROLLER_IP="192.168.75.150"
COMMUNITY="UTMC"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Простой тест чтения SNMP ===${NC}"
echo ""

case "$1" in
    "2.1"|"session")
        echo -e "${YELLOW}Шаг 2.1: Проверка создания SNMP-сессии${NC}"
        echo ""
        read -p "Введите community [UTMC]: " community
        community=${community:-UTMC}
        echo ""
        echo -e "${GREEN}Проверка SNMP соединения с community: $community${NC}"
        echo ""
        
        # Попробуем использовать snmpget если доступен
        if command -v snmpget &> /dev/null; then
            echo "Используется утилита snmpget..."
            snmpget -v 2c -c "$community" "$CONTROLLER_IP" 1.3.6.1.2.1.1.3.0 2>&1
        else
            echo -e "${YELLOW}snmpget недоступен. Нужно установить пакет snmp или собрать test_controller${NC}"
            echo ""
            echo "Установка SNMP утилит:"
            echo "  sudo apt-get install snmp snmp-mibs-downloader"
            echo ""
            echo "Или сборка test_controller:"
            echo "  sudo apt-get install cmake pkg-config libsnmp-dev"
            echo "  mkdir -p build && cd build && cmake .. && make"
        fi
        ;;
        
    "3.1"|"sysuptime")
        echo -e "${YELLOW}Шаг 3.1: Чтение sysUpTime${NC}"
        echo ""
        read -p "Введите community [UTMC]: " community
        community=${community:-UTMC}
        echo ""
        
        if command -v snmpget &> /dev/null; then
            echo -e "${GREEN}Чтение sysUpTime с $CONTROLLER_IP...${NC}"
            snmpget -v 2c -c "$community" "$CONTROLLER_IP" 1.3.6.1.2.1.1.3.0
        else
            echo -e "${RED}snmpget not available${NC}"
        fi
        ;;
        
    "4.1"|"version")
        echo -e "${YELLOW}Шаг 4.1: Чтение версии приложения${NC}"
        echo ""
        read -p "Введите community [UTMC]: " community
        community=${community:-UTMC}
        echo ""
        
        if command -v snmpget &> /dev/null; then
            echo -e "${GREEN}Чтение версии приложения с $CONTROLLER_IP...${NC}"
            snmpget -v 2c -c "$community" "$CONTROLLER_IP" 1.3.6.1.4.1.13267.3.2.1.2
        else
            echo -e "${RED}snmpget not available${NC}"
        fi
        ;;
        
    "4.3"|"mode")
        echo -e "${YELLOW}Шаг 4.3: Чтение operationMode${NC}"
        echo ""
        read -p "Введите community [UTMC]: " community
        community=${community:-UTMC}
        echo ""
        
        if command -v snmpget &> /dev/null; then
            echo -e "${GREEN}Чтение operationMode с $CONTROLLER_IP...${NC}"
            echo "OID: 1.3.6.1.4.1.13267.3.2.4.1.0"
            snmpget -v 2c -c "$community" "$CONTROLLER_IP" 1.3.6.1.4.1.13267.3.2.4.1.0
            echo ""
            echo "Ожидаемые значения:"
            echo "  1 = Standalone"
            echo "  2 = Monitor"
            echo "  3 = UTC Control"
        else
            echo -e "${RED}snmpget недоступен${NC}"
        fi
        ;;
        
    *)
        echo "Использование: $0 <шаг>"
        echo ""
        echo "Доступные шаги:"
        echo "  2.1, session   - Проверка SNMP-сессии"
        echo "  3.1, sysuptime - Чтение sysUpTime"
        echo "  4.1, version   - Чтение версии приложения"
        echo "  4.3, mode      - Чтение operationMode"
        exit 1
        ;;
esac

echo ""
echo -e "${BLUE}=== Шаг выполнен ===${NC}"
