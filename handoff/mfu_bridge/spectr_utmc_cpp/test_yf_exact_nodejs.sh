#!/bin/bash
# Тест SET_YF с точным копированием Node.js логики
# Отправляет команду один раз, без проверок и удержания

set -e

CONTROLLER_IP="${1:-192.168.75.150}"
COMMUNITY="${2:-UTMC}"

echo "=========================================="
echo "Тест SET_YF (точное копирование Node.js логики)"
echo "=========================================="
echo "Контроллер: $CONTROLLER_IP"
echo "Community: $COMMUNITY"
echo ""

# Проверка наличия Node.js утилиты
if ! command -v node &> /dev/null; then
    echo "Ошибка: Node.js не найден"
    exit 1
fi

# Проверка наличия utmc-tester.js
UTMC_TESTER=""
if [ -f "utmc-tester.js" ]; then
    UTMC_TESTER="utmc-tester.js"
elif [ -f "../AI_reaserh/utmc-tester.js" ]; then
    UTMC_TESTER="../AI_reaserh/utmc-tester.js"
elif [ -f "../../AI_reaserh/utmc-tester.js" ]; then
    UTMC_TESTER="../../AI_reaserh/utmc-tester.js"
else
    echo "Ошибка: utmc-tester.js не найден"
    echo "Попробуем использовать snmpset напрямую..."
    USE_SNMPDIRECT=1
fi

echo "Шаг 1: Проверка текущего состояния контроллера"
echo "----------------------------------------"
echo "Режим работы (operationMode):"
node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
    --raw-get "1.3.6.1.4.1.13267.3.2.4.1" --verbose 2>&1 | grep -E "(GET|INTEGER|value)" || true

echo ""
echo "Текущая фаза (utcReplyGn):"
node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
    --raw-get "1.3.6.1.4.1.13267.3.2.5.1.1.3" --verbose 2>&1 | grep -E "(GET|INTEGER|value)" || true

echo ""
echo "Режим мигания (utcReplyFR):"
node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
    --raw-get "1.3.6.1.4.1.13267.3.2.5.1.1.36" --verbose 2>&1 | grep -E "(GET|INTEGER|value)" || true

echo ""
echo "Шаг 2: Отправка команды SET_YF (точное копирование Node.js логики)"
echo "----------------------------------------"
echo "Отправка двух команд в одной транзакции:"
echo "  - operationMode = 3 (UTC Control)"
echo "  - utcControlFF = 1 (включить мигание)"
echo ""

if [ -n "$USE_SNMPDIRECT" ]; then
    RESULT=$(snmpset -v2c -c "$COMMUNITY" "$CONTROLLER_IP" \
        1.3.6.1.4.1.13267.3.2.4.1 i 3 \
        1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 2>&1)
else
    RESULT=$(node "$UTMC_TESTER" --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
        --raw-set "1.3.6.1.4.1.13267.3.2.4.1" --value 3 --type Integer \
        --raw-set "1.3.6.1.4.1.13267.3.2.4.2.1.20" --value 1 --type Integer \
        --verbose 2>&1)
fi

echo "$RESULT"

if echo "$RESULT" | grep -q "success\|INTEGER"; then
    echo ""
    echo "✅ Команда отправлена успешно"
else
    echo ""
    echo "❌ Ошибка отправки команды"
    exit 1
fi

echo ""
echo "Шаг 3: Проверка результата (через 2 секунды)"
echo "----------------------------------------"
sleep 2

echo "Режим работы (operationMode):"
node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
    --raw-get "1.3.6.1.4.1.13267.3.2.4.1" --verbose 2>&1 | grep -E "(GET|INTEGER|value)" || true

echo ""
echo "Режим мигания (utcReplyFR):"
node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
    --raw-get "1.3.6.1.4.1.13267.3.2.5.1.1.36" --verbose 2>&1 | grep -E "(GET|INTEGER|value)" || true

echo ""
echo "Контроль мигания (utcControlFF):"
node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
    --raw-get "1.3.6.1.4.1.13267.3.2.4.2.1.20" --verbose 2>&1 | grep -E "(GET|INTEGER|value)" || true

echo ""
echo "=========================================="
echo "Тест завершён"
echo "=========================================="
echo ""
echo "ВАЖНО: Проверьте визуально, активировалось ли жёлтое мигание на контроллере!"
echo ""
echo "Если мигание не активировалось, проверьте:"
echo "  1. Логи контроллера (resident, snmp_agent)"
echo "  2. Состояние контроллера (режим, фаза, время)"
echo "  3. Конфигурацию контроллера (блокировки, требования)"
