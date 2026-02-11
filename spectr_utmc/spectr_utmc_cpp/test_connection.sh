#!/bin/bash

# Скрипт для тестирования подключения к контроллеру

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
TEST_BIN="${BUILD_DIR}/test_controller"
CONFIG_FILE="${SCRIPT_DIR}/config.json"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Spectr UTMC Controller Connection Test ===${NC}"
echo ""

# Проверка наличия бинарника
if [ ! -f "$TEST_BIN" ]; then
    echo -e "${RED}Error: test_controller not found${NC}"
    echo "Please build the project first:"
    echo "  mkdir -p build && cd build && cmake .. && make"
    exit 1
fi

# Проверка наличия конфига
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${YELLOW}Warning: config.json not found${NC}"
    echo "You can test direct connection using:"
    echo "  $TEST_BIN connect <IP> <COMMUNITY>"
    echo ""
fi

# Меню выбора
echo "Select test mode:"
echo "  1) Test using config.json"
echo "  2) Test direct connection (IP + Community)"
echo "  3) Test trap receiver"
echo "  4) Exit"
echo ""
read -p "Enter choice [1-4]: " choice

case $choice in
    1)
        if [ ! -f "$CONFIG_FILE" ]; then
            echo -e "${RED}Error: config.json not found${NC}"
            exit 1
        fi
        echo ""
        echo -e "${GREEN}Running test with config.json...${NC}"
        "$TEST_BIN" test "$CONFIG_FILE"
        ;;
    2)
        read -p "Enter controller IP address: " ip
        read -p "Enter SNMP community [UTMC]: " community
        community=${community:-UTMC}
        echo ""
        echo -e "${GREEN}Testing connection to $ip with community '$community'...${NC}"
        "$TEST_BIN" connect "$ip" "$community"
        ;;
    3)
        read -p "Enter trap port [10162]: " port
        port=${port:-10162}
        read -p "Enter SNMP community [UTMC]: " community
        community=${community:-UTMC}
        echo ""
        echo -e "${GREEN}Starting trap receiver on port $port...${NC}"
        "$TEST_BIN" traps "$port" "$community"
        ;;
    4)
        echo "Exiting..."
        exit 0
        ;;
    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}Test completed${NC}"
