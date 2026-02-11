#!/bin/bash
#
# UTMC/UG405 SNMP Test Commands
# Скрипт для быстрого тестирования различных гипотез формирования OID
#
# Использование:
#   ./test-commands.sh <IP> [COMMUNITY] [SCN]
#   ./test-commands.sh 192.168.1.100 UTMC CO1111
#

set -e

# Параметры
IP="${1:-192.168.1.100}"
COMMUNITY="${2:-UTMC}"
SCN="${3:-CO1111}"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Базовые OID
OID_OPERATION_MODE="1.3.6.1.4.1.13267.3.2.4.1"
OID_CONTROL_FN="1.3.6.1.4.1.13267.3.2.4.2.1.5"
OID_CONTROL_LO="1.3.6.1.4.1.13267.3.2.4.2.1.11"
OID_CONTROL_FF="1.3.6.1.4.1.13267.3.2.4.2.1.20"
OID_REPLY_GN="1.3.6.1.4.1.13267.3.2.5.1.1.3"
OID_UTMC_BASE="1.3.6.1.4.1.13267"

# Преобразование SCN в ASCII коды для OID
scn_to_ascii() {
    local scn="$1"
    local result=""
    for (( i=0; i<${#scn}; i++ )); do
        char="${scn:$i:1}"
        ascii=$(printf '%d' "'$char")
        result="${result}.${ascii}"
    done
    echo "$result"
}

SCN_ASCII=$(scn_to_ascii "$SCN")

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         UTMC/UG405 SNMP Test Script                        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "IP Address:  ${GREEN}$IP${NC}"
echo -e "Community:   ${GREEN}$COMMUNITY${NC}"
echo -e "SCN:         ${GREEN}$SCN${NC}"
echo -e "SCN ASCII:   ${GREEN}$SCN_ASCII${NC}"
echo ""

run_test() {
    local name="$1"
    local cmd="$2"
    
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  $name${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Command:${NC} $cmd"
    echo ""
    
    if eval "$cmd" 2>&1; then
        echo -e "\n${GREEN}✓ Success${NC}"
    else
        echo -e "\n${RED}✗ Failed${NC}"
    fi
    echo ""
}

# ==================== ДИАГНОСТИКА ====================

echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  ДИАГНОСТИКА${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"

run_test "Тест связи (sysDescr)" \
    "snmpget -v2c -c $COMMUNITY $IP 1.3.6.1.2.1.1.1.0"

run_test "SNMP Walk по UTMC дереву (первые 20 OID)" \
    "snmpwalk -v2c -c $COMMUNITY $IP $OID_UTMC_BASE 2>/dev/null | head -20"

run_test "Текущий режим работы" \
    "snmpget -v2c -c $COMMUNITY $IP $OID_OPERATION_MODE"

run_test "Текущая фаза (без индекса)" \
    "snmpget -v2c -c $COMMUNITY $IP $OID_REPLY_GN"

run_test "Текущая фаза (с индексом .1)" \
    "snmpget -v2c -c $COMMUNITY $IP ${OID_REPLY_GN}.1"

# ==================== ТЕСТЫ SET КОМАНД ====================

echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  ТЕСТЫ SET КОМАНД (разные форматы OID)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"

echo -e "${RED}ВНИМАНИЕ: Следующие команды будут менять состояние контроллера!${NC}"
echo -e "Нажмите Enter для продолжения или Ctrl+C для отмены..."
read -r

# Гипотеза 1: Без SCN (как в рабочем коде)
run_test "Гипотеза 1: SET без SCN (рабочий вариант из spectr_utmc.js)" \
    "snmpset -v2c -c $COMMUNITY $IP \
    $OID_OPERATION_MODE i 3 \
    $OID_CONTROL_FN x 02"

sleep 2

# Гипотеза 2: С индексом .1
run_test "Гипотеза 2: SET с индексом .1" \
    "snmpset -v2c -c $COMMUNITY $IP \
    $OID_OPERATION_MODE i 3 \
    ${OID_CONTROL_FN}.1 x 04"

sleep 2

# Гипотеза 3: С SCN в ASCII
run_test "Гипотеза 3: SET с SCN в ASCII ($SCN -> $SCN_ASCII)" \
    "snmpset -v2c -c $COMMUNITY $IP \
    $OID_OPERATION_MODE i 3 \
    ${OID_CONTROL_FN}${SCN_ASCII} x 08"

sleep 2

# Гипотеза 4: С длиной + SCN
SCN_LEN=${#SCN}
run_test "Гипотеза 4: SET с длиной + SCN (.${SCN_LEN}${SCN_ASCII})" \
    "snmpset -v2c -c $COMMUNITY $IP \
    $OID_OPERATION_MODE i 3 \
    ${OID_CONTROL_FN}.${SCN_LEN}${SCN_ASCII} x 10"

sleep 2

# Гипотеза 5: С индексом .0
run_test "Гипотеза 5: SET с индексом .0" \
    "snmpset -v2c -c $COMMUNITY $IP \
    $OID_OPERATION_MODE i 3 \
    ${OID_CONTROL_FN}.0 x 01"

# ==================== ВОЗВРАТ В ИСХОДНОЕ СОСТОЯНИЕ ====================

echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  ВОЗВРАТ В ЛОКАЛЬНЫЙ РЕЖИМ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"

run_test "Переключение в локальный режим (operationMode = 0)" \
    "snmpset -v2c -c $COMMUNITY $IP $OID_OPERATION_MODE i 0"

# ==================== ИТОГИ ====================

echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  ИТОГИ ТЕСТИРОВАНИЯ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"

echo "Проверьте вывод каждого теста выше."
echo "Успешные команды получат ответ с подтверждением значения."
echo "Неуспешные команды получат ошибки типа:"
echo "  - noSuchName: неверный OID"
echo "  - badValue: неверный тип или значение"
echo "  - genErr: общая ошибка"
echo "  - timeout: нет ответа"
echo ""
echo -e "${GREEN}Тестирование завершено.${NC}"
