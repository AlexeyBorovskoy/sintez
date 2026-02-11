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

echo -e "${BLUE}=== Simple SNMP Read Test ===${NC}"
echo ""

case "$1" in
    "2.1"|"session")
        echo -e "${YELLOW}Step 2.1: Testing SNMP session creation${NC}"
        echo ""
        read -p "Enter community string [UTMC]: " community
        community=${community:-UTMC}
        echo ""
        echo -e "${GREEN}Testing SNMP connection with community: $community${NC}"
        echo ""
        
        # Попробуем использовать snmpget если доступен
        if command -v snmpget &> /dev/null; then
            echo "Using snmpget utility..."
            snmpget -v 2c -c "$community" "$CONTROLLER_IP" 1.3.6.1.2.1.1.3.0 2>&1
        else
            echo -e "${YELLOW}snmpget not available. Need to install snmp package or build test_controller${NC}"
            echo ""
            echo "To install SNMP utilities:"
            echo "  sudo apt-get install snmp snmp-mibs-downloader"
            echo ""
            echo "Or build test_controller:"
            echo "  sudo apt-get install cmake pkg-config libsnmp-dev"
            echo "  mkdir -p build && cd build && cmake .. && make"
        fi
        ;;
        
    "3.1"|"sysuptime")
        echo -e "${YELLOW}Step 3.1: Reading sysUpTime${NC}"
        echo ""
        read -p "Enter community string [UTMC]: " community
        community=${community:-UTMC}
        echo ""
        
        if command -v snmpget &> /dev/null; then
            echo -e "${GREEN}Reading sysUpTime from $CONTROLLER_IP...${NC}"
            snmpget -v 2c -c "$community" "$CONTROLLER_IP" 1.3.6.1.2.1.1.3.0
        else
            echo -e "${RED}snmpget not available${NC}"
        fi
        ;;
        
    "4.1"|"version")
        echo -e "${YELLOW}Step 4.1: Reading application version${NC}"
        echo ""
        read -p "Enter community string [UTMC]: " community
        community=${community:-UTMC}
        echo ""
        
        if command -v snmpget &> /dev/null; then
            echo -e "${GREEN}Reading application version from $CONTROLLER_IP...${NC}"
            snmpget -v 2c -c "$community" "$CONTROLLER_IP" 1.3.6.1.4.1.13267.3.2.1.2
        else
            echo -e "${RED}snmpget not available${NC}"
        fi
        ;;
        
    "4.3"|"mode")
        echo -e "${YELLOW}Step 4.3: Reading operation mode${NC}"
        echo ""
        read -p "Enter community string [UTMC]: " community
        community=${community:-UTMC}
        echo ""
        
        if command -v snmpget &> /dev/null; then
            echo -e "${GREEN}Reading operation mode from $CONTROLLER_IP...${NC}"
            echo "OID: 1.3.6.1.4.1.13267.3.2.4.1.0"
            snmpget -v 2c -c "$community" "$CONTROLLER_IP" 1.3.6.1.4.1.13267.3.2.4.1.0
            echo ""
            echo "Expected values:"
            echo "  1 = Standalone"
            echo "  2 = Monitor"
            echo "  3 = UTC Control"
        else
            echo -e "${RED}snmpget not available${NC}"
        fi
        ;;
        
    *)
        echo "Usage: $0 <step>"
        echo ""
        echo "Available steps:"
        echo "  2.1, session   - Test SNMP session"
        echo "  3.1, sysuptime - Read sysUpTime"
        echo "  4.1, version   - Read application version"
        echo "  4.3, mode      - Read operation mode"
        exit 1
        ;;
esac

echo ""
echo -e "${BLUE}=== Step completed ===${NC}"
