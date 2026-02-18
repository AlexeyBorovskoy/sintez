#!/bin/bash
# Тестирование различных вариантов OID для Operation Mode и Controller Time

ADDRESS="192.168.75.150"
COMMUNITY="UTMC"

echo "=== Проверка вариантов OID ==="
echo "Адрес: $ADDRESS"
echo "SNMP community: $COMMUNITY"
echo ""

# Варианты для Operation Mode
echo "1. Проверка OID operationMode:"
echo "   a) 1.3.6.1.4.1.13267.3.2.4.1 (без .0)"
./build/test_controller get "$ADDRESS" "$COMMUNITY" "1.3.6.1.4.1.13267.3.2.4.1" 2>&1 | grep -E "(OK|ERROR|Value|No Such)"

echo "   b) 1.3.6.1.4.1.13267.3.2.4.1.0 (с .0)"
./build/test_controller get "$ADDRESS" "$COMMUNITY" "1.3.6.1.4.1.13267.3.2.4.1.0" 2>&1 | grep -E "(OK|ERROR|Value|No Such)"

echo ""
echo "2. Проверка OID времени контроллера:"
echo "   a) 1.3.6.1.4.1.13267.3.2.3.2 (без .0)"
./build/test_controller get "$ADDRESS" "$COMMUNITY" "1.3.6.1.4.1.13267.3.2.3.2" 2>&1 | grep -E "(OK|ERROR|Value|No Such)"

echo "   b) 1.3.6.1.4.1.13267.3.2.3.2.0 (с .0)"
./build/test_controller get "$ADDRESS" "$COMMUNITY" "1.3.6.1.4.1.13267.3.2.3.2.0" 2>&1 | grep -E "(OK|ERROR|Value|No Such)"

echo ""
echo "=== Тест завершен ==="
