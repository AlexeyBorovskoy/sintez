#!/bin/bash
# Тестирование различных вариантов OID для Operation Mode и Controller Time

ADDRESS="192.168.75.150"
COMMUNITY="UTMC"

echo "=== Testing OID Variants ==="
echo "Address: $ADDRESS"
echo "Community: $COMMUNITY"
echo ""

# Варианты для Operation Mode
echo "1. Testing Operation Mode OIDs:"
echo "   a) 1.3.6.1.4.1.13267.3.2.4.1 (without .0)"
./build/test_controller get "$ADDRESS" "$COMMUNITY" "1.3.6.1.4.1.13267.3.2.4.1" 2>&1 | grep -E "(OK|ERROR|Value|No Such)"

echo "   b) 1.3.6.1.4.1.13267.3.2.4.1.0 (with .0)"
./build/test_controller get "$ADDRESS" "$COMMUNITY" "1.3.6.1.4.1.13267.3.2.4.1.0" 2>&1 | grep -E "(OK|ERROR|Value|No Such)"

echo ""
echo "2. Testing Controller Time OIDs:"
echo "   a) 1.3.6.1.4.1.13267.3.2.3.2 (without .0)"
./build/test_controller get "$ADDRESS" "$COMMUNITY" "1.3.6.1.4.1.13267.3.2.3.2" 2>&1 | grep -E "(OK|ERROR|Value|No Such)"

echo "   b) 1.3.6.1.4.1.13267.3.2.3.2.0 (with .0)"
./build/test_controller get "$ADDRESS" "$COMMUNITY" "1.3.6.1.4.1.13267.3.2.3.2.0" 2>&1 | grep -E "(OK|ERROR|Value|No Such)"

echo ""
echo "=== Test Complete ==="
