#!/bin/bash

# Проверка формата OID с SCN (без подключения к контроллеру)

SCN="CO11111"

build_oid_with_scn() {
    local base_oid=$1
    local scn=$2
    local oid="${base_oid}.1"  # timestamp = 1 (NOW)
    
    # Добавляем ASCII коды символов SCN
    for (( i=0; i<${#scn}; i++ )); do
        char="${scn:$i:1}"
        ascii_code=$(printf "%d" "'$char")
        oid="${oid}.${ascii_code}"
    done
    
    echo "$oid"
}

echo "=== ПРОВЕРКА ФОРМАТА OID С SCN ==="
echo "SCN: $SCN"
echo ""

# Примеры OID
BASE_OID_PHASE="1.3.6.1.4.1.13267.3.2.4.2.1.5"
BASE_OID_AF="1.3.6.1.4.1.13267.3.2.4.2.1.20"
BASE_OID_GET_PHASE="1.3.6.1.4.1.13267.3.2.5.1.1.3"
BASE_OID_GET_AF="1.3.6.1.4.1.13267.3.2.5.1.1.36"

OID_PHASE=$(build_oid_with_scn "$BASE_OID_PHASE" "$SCN")
OID_AF=$(build_oid_with_scn "$BASE_OID_AF" "$SCN")
OID_GET_PHASE=$(build_oid_with_scn "$BASE_OID_GET_PHASE" "$SCN")
OID_GET_AF=$(build_oid_with_scn "$BASE_OID_GET_AF" "$SCN")

echo "SetPhase OID:"
echo "  $OID_PHASE"
echo ""

echo "SetAF OID:"
echo "  $OID_AF"
echo ""

echo "GetPhase OID:"
echo "  $OID_GET_PHASE"
echo ""

echo "GetAF OID:"
echo "  $OID_GET_AF"
echo ""

# Проверка формата
EXPECTED_SUFFIX=".1.67.79.49.49.49.49.49"  # .1.C.O.1.1.1.1.1
echo "=== ПРОВЕРКА ФОРМАТА ==="
echo "Ожидаемое окончание: $EXPECTED_SUFFIX"
echo ""

if [[ "$OID_PHASE" == *"$EXPECTED_SUFFIX" ]]; then
    echo "✓ Формат OID правильный!"
    echo ""
    echo "Расшифровка ASCII кодов:"
    echo "  67 = 'C'"
    echo "  79 = 'O'"
    echo "  49 = '1' (x5)"
    echo ""
    echo "✓ Готово к тестированию на контроллере!"
else
    echo "✗ Формат OID неправильный!"
    echo "  Ожидалось окончание: $EXPECTED_SUFFIX"
    echo "  Получено: ${OID_PHASE##*.}"
    exit 1
fi
