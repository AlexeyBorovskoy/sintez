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

echo -e "${BLUE}=== Spectr UTMC Read Test - Step by Step ===${NC}"
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
    "1.1"|"ping")
        echo -e "${YELLOW}Step 1.1: Checking controller availability${NC}"
        echo ""
        ping -c 2 "$CONTROLLER_IP"
        echo ""
        echo -e "${GREEN}Step completed. Check results above.${NC}"
        ;;
        
    "1.2"|"port")
        echo -e "${YELLOW}Step 1.2: Checking SNMP port${NC}"
        echo ""
        echo "Checking UDP port 161..."
        nc -zv -u -w 3 "$CONTROLLER_IP" 161
        echo ""
        echo -e "${GREEN}Step completed. Check results above.${NC}"
        ;;
        
    "2.1"|"session")
        echo -e "${YELLOW}Step 2.1: Creating SNMP session${NC}"
        echo ""
        read -p "Enter community string [UTMC]: " community
        community=${community:-UTMC}
        echo ""
        echo -e "${GREEN}Testing session creation with community: $community${NC}"
        echo ""
        "$TEST_BIN" connect "$CONTROLLER_IP" "$community" 2>&1 | head -20
        echo ""
        echo -e "${GREEN}Step completed. Check if 'Session created successfully' appears above.${NC}"
        ;;
        
    "3.1"|"sysuptime")
        echo -e "${YELLOW}Step 3.1: Reading sysUpTime${NC}"
        echo ""
        read -p "Enter community string [UTMC]: " community
        community=${community:-UTMC}
        echo ""
        echo -e "${GREEN}Reading sysUpTime from $CONTROLLER_IP...${NC}"
        echo ""
        "$TEST_BIN" connect "$CONTROLLER_IP" "$community" 2>&1 | grep -A 10 "sysUpTime"
        echo ""
        echo -e "${GREEN}Step completed. Check results above.${NC}"
        ;;
        
    "4.1"|"version")
        echo -e "${YELLOW}Step 4.1: Reading application version${NC}"
        echo ""
        read -p "Enter community string [UTMC]: " community
        community=${community:-UTMC}
        echo ""
        echo -e "${GREEN}Reading application version from $CONTROLLER_IP...${NC}"
        echo ""
        "$TEST_BIN" connect "$CONTROLLER_IP" "$community" 2>&1 | grep -A 10 "Application Version"
        echo ""
        echo -e "${GREEN}Step completed. Check results above.${NC}"
        ;;
        
    "4.3"|"mode")
        echo -e "${YELLOW}Step 4.3: Reading operation mode${NC}"
        echo ""
        read -p "Enter community string [UTMC]: " community
        community=${community:-UTMC}
        echo ""
        echo -e "${GREEN}Reading operation mode from $CONTROLLER_IP...${NC}"
        echo ""
        "$TEST_BIN" connect "$CONTROLLER_IP" "$community" 2>&1 | grep -A 15 "Operation Mode"
        echo ""
        echo -e "${GREEN}Step completed. Check results above.${NC}"
        ;;
        
    "4.5"|"time")
        echo -e "${YELLOW}Step 4.5: Reading controller time${NC}"
        echo ""
        read -p "Enter community string [UTMC]: " community
        community=${community:-UTMC}
        echo ""
        echo -e "${GREEN}Reading controller time from $CONTROLLER_IP...${NC}"
        echo ""
        "$TEST_BIN" connect "$CONTROLLER_IP" "$community" 2>&1 | grep -A 10 "Controller Time"
        echo ""
        echo -e "${GREEN}Step completed. Check results above.${NC}"
        ;;
        
    "5.1"|"phase")
        echo -e "${YELLOW}Step 5.1: Reading current phase${NC}"
        echo ""
        echo -e "${YELLOW}Note: This OID may require SCN parameter${NC}"
        read -p "Enter community string [UTMC]: " community
        community=${community:-UTMC}
        echo ""
        echo -e "${GREEN}Reading current phase from $CONTROLLER_IP...${NC}"
        echo ""
        "$TEST_BIN" connect "$CONTROLLER_IP" "$community" 2>&1 | grep -A 10 "phase\|Phase\|GN"
        echo ""
        echo -e "${GREEN}Step completed. Check results above.${NC}"
        ;;
        
    "full"|"all")
        echo -e "${YELLOW}Running full read test${NC}"
        echo ""
        read -p "Enter community string [UTMC]: " community
        community=${community:-UTMC}
        echo ""
        echo -e "${GREEN}Running complete connectivity test...${NC}"
        echo ""
        "$TEST_BIN" connect "$CONTROLLER_IP" "$community"
        echo ""
        echo -e "${GREEN}Full test completed.${NC}"
        ;;
        
    *)
        echo "Usage: $0 <step_number>"
        echo ""
        echo "Available steps:"
        echo "  1.1, ping      - Check controller availability"
        echo "  1.2, port      - Check SNMP port"
        echo "  2.1, session   - Create SNMP session"
        echo "  3.1, sysuptime - Read sysUpTime"
        echo "  4.1, version   - Read application version"
        echo "  4.3, mode      - Read operation mode"
        echo "  4.5, time      - Read controller time"
        echo "  5.1, phase     - Read current phase"
        echo "  full, all      - Run full read test"
        echo ""
        echo "Example: $0 2.1"
        exit 1
        ;;
esac

echo ""
echo -e "${BLUE}=== Step completed ===${NC}"
echo "Review results above and update TEST_READ_PLAN.md"
