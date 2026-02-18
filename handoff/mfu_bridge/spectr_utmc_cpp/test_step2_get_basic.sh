#!/bin/bash

# ШАГ 2: Тестирование GET операций БЕЗ SCN

CONTROLLER_IP="192.168.75.150"
COMMUNITY="UTMC"

echo "=== ШАГ 2: GET операции БЕЗ SCN ==="
echo "Контроллер: $CONTROLLER_IP"
echo ""

# GetTime (не требует SCN)
echo "1. GetTime (не требует SCN):"
echo "   OID: 1.3.6.1.4.1.13267.3.2.3.2.0"
./build/test_controller get "$CONTROLLER_IP" "$COMMUNITY" "1.3.6.1.4.1.13267.3.2.3.2.0"
echo ""

# Operation Mode (не требует SCN)
echo "2. Operation Mode (не требует SCN):"
echo "   OID: 1.3.6.1.4.1.13267.3.2.4.1.0"
./build/test_controller get "$CONTROLLER_IP" "$COMMUNITY" "1.3.6.1.4.1.13267.3.2.4.1.0"
echo ""

echo "✓ ШАГ 2 завершен!"
