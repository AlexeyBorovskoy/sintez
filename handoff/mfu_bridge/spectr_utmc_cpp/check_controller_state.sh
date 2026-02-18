#!/bin/bash
# Скрипт для проверки состояния контроллера

set -e

CONTROLLER_IP="${1:-192.168.75.150}"
COMMUNITY="${2:-UTMC}"

echo "=========================================="
echo "Проверка состояния контроллера"
echo "=========================================="
echo "Контроллер: $CONTROLLER_IP"
echo "Community: $COMMUNITY"
echo ""

# Проверка доступности контроллера
echo "1. Проверка доступности контроллера..."
if ping -c 1 -W 2 "$CONTROLLER_IP" > /dev/null 2>&1; then
    echo "   ✅ Контроллер доступен"
else
    echo "   ❌ Контроллер недоступен"
    exit 1
fi

echo ""
echo "2. Проверка режима работы (operationMode)..."
OPERATION_MODE=$(snmpget -v2c -c "$COMMUNITY" -Oqv "$CONTROLLER_IP" 1.3.6.1.4.1.13267.3.2.4.1 2>/dev/null || echo "ERROR")
case "$OPERATION_MODE" in
    0) echo "   Режим: Local (0)" ;;
    1) echo "   Режим: Standalone (1)" ;;
    2) echo "   Режим: Monitor (2)" ;;
    3) echo "   Режим: UTC Control (3)" ;;
    *) echo "   Режим: Неизвестный ($OPERATION_MODE)" ;;
esac

echo ""
echo "3. Проверка текущей фазы (utcReplyGn)..."
CURRENT_PHASE=$(snmpget -v2c -c "$COMMUNITY" -Oqv "$CONTROLLER_IP" 1.3.6.1.4.1.13267.3.2.5.1.1.3 2>/dev/null || echo "ERROR")
if [ "$CURRENT_PHASE" != "ERROR" ]; then
    echo "   Текущая фаза: $CURRENT_PHASE"
else
    echo "   ❌ Не удалось получить текущую фазу"
fi

echo ""
echo "4. Проверка длительности фазы (utcReplyStageLength)..."
STAGE_LENGTH=$(snmpget -v2c -c "$COMMUNITY" -Oqv "$CONTROLLER_IP" 1.3.6.1.4.1.13267.3.2.5.1.1.19 2>/dev/null || echo "ERROR")
if [ "$STAGE_LENGTH" != "ERROR" ]; then
    echo "   Длительность фазы: $STAGE_LENGTH сек"
else
    echo "   ❌ Не удалось получить длительность фазы"
fi

echo ""
echo "5. Проверка счётчика фазы (utcReplyStageCounter)..."
STAGE_COUNTER=$(snmpget -v2c -c "$COMMUNITY" -Oqv "$CONTROLLER_IP" 1.3.6.1.4.1.13267.3.2.5.1.1.20 2>/dev/null || echo "ERROR")
if [ "$STAGE_COUNTER" != "ERROR" ]; then
    echo "   Счётчик фазы: $STAGE_COUNTER сек"
else
    echo "   ❌ Не удалось получить счётчик фазы"
fi

echo ""
echo "6. Проверка режима мигания (utcReplyFR)..."
REPLY_FR=$(snmpget -v2c -c "$COMMUNITY" -Oqv "$CONTROLLER_IP" 1.3.6.1.4.1.13267.3.2.5.1.1.36 2>/dev/null || echo "ERROR")
if [ "$REPLY_FR" != "ERROR" ]; then
    if [ "$REPLY_FR" = "1" ]; then
        echo "   ✅ Режим мигания активирован (utcReplyFR=1)"
    else
        echo "   ⚠️  Режим мигания не активирован (utcReplyFR=$REPLY_FR)"
    fi
else
    echo "   ❌ Не удалось получить режим мигания"
fi

echo ""
echo "7. Проверка контроля мигания (utcControlFF)..."
CONTROL_FF=$(snmpget -v2c -c "$COMMUNITY" -Oqv "$CONTROLLER_IP" 1.3.6.1.4.1.13267.3.2.4.2.1.20 2>/dev/null || echo "ERROR")
if [ "$CONTROL_FF" != "ERROR" ]; then
    if [ "$CONTROL_FF" = "1" ]; then
        echo "   ✅ Контроль мигания установлен (utcControlFF=1)"
    else
        echo "   ⚠️  Контроль мигания не установлен (utcControlFF=$CONTROL_FF)"
    fi
else
    echo "   ❌ Не удалось получить контроль мигания"
fi

echo ""
echo "=========================================="
echo "Сводка состояния контроллера"
echo "=========================================="
echo "Режим работы: $OPERATION_MODE"
echo "Текущая фаза: $CURRENT_PHASE"
echo "Длительность фазы: $STAGE_LENGTH сек"
echo "Счётчик фазы: $STAGE_COUNTER сек"
echo "Режим мигания (utcReplyFR): $REPLY_FR"
echo "Контроль мигания (utcControlFF): $CONTROL_FF"
echo ""

if [ "$OPERATION_MODE" = "3" ] && [ "$CONTROL_FF" = "1" ] && [ "$REPLY_FR" != "1" ]; then
    echo "⚠️  ВНИМАНИЕ: Команда SET_YF отправлена (operationMode=3, utcControlFF=1),"
    echo "   но режим мигания не активирован (utcReplyFR≠1)"
    echo "   Это может означать, что контроллер не готов принять команду"
fi
