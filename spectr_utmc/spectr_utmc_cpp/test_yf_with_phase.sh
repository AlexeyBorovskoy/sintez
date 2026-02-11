#!/bin/bash
#
# Тест жёлтого мигания с предварительной установкой фазы
# (как в оригинальном Node.js коде)
#

CONTROLLER_IP="192.168.75.150"
COMMUNITY="UTMC"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Тест жёлтого мигания с установкой фазы (как в Node.js)  ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

cd "$SCRIPT_DIR/../AI_reaserh" || exit 1

# Шаг 1: Анализ текущего состояния
echo "=== Шаг 1: Анализ текущего состояния ==="
node analyze_state_simple.js "$CONTROLLER_IP" "$COMMUNITY"

echo ""
echo "Продолжаем тестирование..."
sleep 2

# Шаг 2: Перевод в режим UTC Control
echo ""
echo "=== Шаг 2: Перевод в режим UTC Control ==="
echo "Установка режима UTC Control (3)..."
node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
    --raw-set "1.3.6.1.4.1.13267.3.2.4.1" --value 3 --type Integer 2>&1 | grep -E "(SET|success|Failed)" || true

sleep 2

# Шаг 3: Установка фазы (например, фаза 1)
echo ""
echo "=== Шаг 3: Установка фазы (как в SET_PHASE) ==="
echo "Установка фазы 1 (битовая маска 0x01)..."
node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
    --raw-set "1.3.6.1.4.1.13267.3.2.4.1" --value 3 --type Integer \
    --raw-set "1.3.6.1.4.1.13267.3.2.4.2.1.5" --value "01" --type HexString \
    --verbose 2>&1 | grep -E "(SET|success|Failed)" || true

echo "Ожидание активации фазы (5 сек)..."
sleep 5

# Проверка текущей фазы
echo ""
echo "Текущая фаза:"
node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
    --raw-get "1.3.6.1.4.1.13267.3.2.5.1.1.3" 2>&1 | grep -E "(INTEGER|Hex-STRING)" | head -1 || echo "Ошибка чтения"

# Шаг 4: Активация мигания (как в SET_YF)
echo ""
echo "=== Шаг 4: Активация жёлтого мигания (как в SET_YF) ==="
echo "⚠️  ВНИМАНИЕ: Будет активировано жёлтое мигание!"
echo "⚠️  Визуально контролируйте контроллер!"
echo ""
echo "Начинаем активацию через 3 секунды..."
sleep 3

# Отправка команды SET_YF (точно как в оригинальном коде)
echo ""
echo "[0 сек] Отправка команды SET_YF (однократно, как в Node.js)..."
node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
    --raw-set "1.3.6.1.4.1.13267.3.2.4.1" --value 3 --type Integer \
    --raw-set "1.3.6.1.4.1.13267.3.2.4.2.1.20" --value 1 --type Integer \
    --verbose 2>&1 | grep -E "(SET|success|Failed)" || true

echo ""
echo "Ожидание активации мигания (10 секунд)..."
for i in {1..10}; do
    sleep 1
    echo -n "."
done
echo ""

# Проверка режима мигания
echo ""
echo "=== Проверка режима мигания ==="
echo "utcReplyFR (режим мигания):"
node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
    --raw-get "1.3.6.1.4.1.13267.3.2.5.1.1.36" 2>&1 | grep -E "(INTEGER|Hex-STRING)" | head -1 || echo "Ошибка чтения"

echo ""
echo "Текущая фаза:"
node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
    --raw-get "1.3.6.1.4.1.13267.3.2.5.1.1.3" 2>&1 | grep -E "(INTEGER|Hex-STRING)" | head -1 || echo "Ошибка чтения"

# Шаг 5: Отключение мигания
echo ""
echo "=== Шаг 5: Отключение мигания ==="
echo "Отправка команды отключения..."
node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
    --raw-set "1.3.6.1.4.1.13267.3.2.4.1" --value 3 --type Integer \
    --raw-set "1.3.6.1.4.1.13267.3.2.4.2.1.20" --value 0 --type Integer \
    --verbose 2>&1 | grep -E "(SET|success|Failed)" || true

sleep 2

echo ""
echo "=== Финальная проверка ==="
node analyze_state_simple.js "$CONTROLLER_IP" "$COMMUNITY"

echo ""
echo "✓ Тест завершён"
echo ""
echo "Проверьте визуально:"
echo "  1. Активировалась ли фаза 1?"
echo "  2. Активировалось ли жёлтое мигание после команды SET_YF?"
echo "  3. Отключилось ли мигание после команды отключения?"
