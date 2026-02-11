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

echo -e "${GREEN}=== Spectr UTMC Test Step Runner ===${NC}"
echo ""

# Проверка наличия бинарника
if [ ! -f "$TEST_BIN" ]; then
    echo -e "${RED}Error: test_controller not found${NC}"
    echo "Building project..."
    mkdir -p "$BUILD_DIR" && cd "$BUILD_DIR" && cmake .. && make
    if [ $? -ne 0 ]; then
        echo -e "${RED}Build failed!${NC}"
        exit 1
    fi
    cd "$SCRIPT_DIR"
fi

case "$1" in
    "0.1"|"prep1")
        echo -e "${YELLOW}Step 0.1: Checking controller availability${NC}"
        echo ""
        ping -c 4 "$CONTROLLER_IP"
        ;;
        
    "0.2"|"prep2")
        echo -e "${YELLOW}Step 0.2: Checking ports${NC}"
        echo ""
        echo "Checking SSH (22)..."
        nc -zv -w 3 "$CONTROLLER_IP" 22
        echo ""
        echo "Checking HTTPS (443)..."
        nc -zv -w 3 "$CONTROLLER_IP" 443
        echo ""
        echo "Checking SNMP (161 UDP)..."
        nc -zv -w 3 -u "$CONTROLLER_IP" 161
        ;;
        
    "1.1"|"community")
        echo -e "${YELLOW}Step 1.1: Testing community strings${NC}"
        echo ""
        read -p "Enter community string to test [UTMC]: " community
        community=${community:-UTMC}
        echo ""
        echo -e "${GREEN}Testing with community: $community${NC}"
        "$TEST_BIN" connect "$CONTROLLER_IP" "$community"
        ;;
        
    "2.1"|"sysuptime")
        echo -e "${YELLOW}Step 2.1: Testing sysUpTime${NC}"
        echo ""
        read -p "Enter community string [UTMC]: " community
        community=${community:-UTMC}
        echo ""
        "$TEST_BIN" connect "$CONTROLLER_IP" "$community" | grep -A 5 "sysUpTime"
        ;;
        
    "4.1"|"traps")
        echo -e "${YELLOW}Step 4.1: Testing trap receiver${NC}"
        echo ""
        read -p "Enter trap port [10162]: " port
        port=${port:-10162}
        read -p "Enter community string [UTMC]: " community
        community=${community:-UTMC}
        echo ""
        echo -e "${GREEN}Starting trap receiver on port $port...${NC}"
        echo "Press Ctrl+C to stop"
        "$TEST_BIN" traps "$port" "$community"
        ;;
        
    "full")
        echo -e "${YELLOW}Running full connectivity test${NC}"
        echo ""
        read -p "Enter community string [UTMC]: " community
        community=${community:-UTMC}
        echo ""
        "$TEST_BIN" connect "$CONTROLLER_IP" "$community"
        ;;
        
    *)
        echo "Usage: $0 <step_number>"
        echo ""
        echo "Available steps:"
        echo "  0.1, prep1     - Check controller availability (ping)"
        echo "  0.2, prep2     - Check ports (SSH, HTTPS, SNMP)"
        echo "  1.1, community - Test community string"
        echo "  2.1, sysuptime - Test sysUpTime GET"
        echo "  4.1, traps     - Test trap receiver"
        echo "  full           - Run full connectivity test"
        echo ""
        echo "Example: $0 1.1"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}Step completed${NC}"
