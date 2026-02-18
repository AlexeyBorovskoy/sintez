#!/bin/bash
#
# Тест жёлтого мигания с предварительным анализом состояния
#

CONTROLLER_IP="192.168.75.150"
COMMUNITY="UTMC"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Тест жёлтого мигания с анализом состояния контроллера  ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Шаг 1: Анализ текущего состояния
echo "=== Шаг 1: Анализ текущего состояния ==="
cd "$SCRIPT_DIR/../AI_reaserh" || exit 1
node analyze_state_simple.js "$CONTROLLER_IP" "$COMMUNITY"

echo ""
echo "Продолжаем тестирование автоматически..."
# Автоматическое продолжение (раскомментируйте для интерактивного режима):
# read -p "Продолжить тестирование? (y/n) " -n 1 -r
# echo ""
# if [[ ! $REPLY =~ ^[Yy]$ ]]; then
#     echo "Тестирование отменено"
#     exit 0
# fi

# Шаг 2: Перевод в режим UTC Control (если необходимо)
echo ""
echo "=== Шаг 2: Перевод в режим UTC Control ==="
echo "Проверка текущего режима..."

current_mode=$(node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" --status 2>&1 | grep "Operation Mode" | grep -o "[0-9]")

if [ -z "$current_mode" ]; then
    echo "Ошибка: не удалось получить режим работы"
    exit 1
fi

echo "Текущий режим: $current_mode"

if [ "$current_mode" != "3" ]; then
    echo "Перевод контроллера в режим UTC Control (3)..."
    node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
        --raw-set "1.3.6.1.4.1.13267.3.2.4.1" --value 3 --type Integer \
        --verbose 2>&1 | grep -E "(SET|success|Failed)" || true
    
    echo "Ожидание стабилизации режима (2 сек)..."
    sleep 2
    
    # Проверка режима
    new_mode=$(node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" --status 2>&1 | grep "Operation Mode" | grep -o "[0-9]")
    echo "Новый режим: $new_mode"
    
    if [ "$new_mode" != "3" ]; then
        echo "⚠ Предупреждение: режим не изменился на UTC Control"
    fi
else
    echo "✓ Контроллер уже в режиме UTC Control"
fi

# Шаг 3: Активация мигания с удержанием
echo ""
echo "=== Шаг 3: Активация жёлтого мигания (удержание 60 сек) ==="
echo "⚠️  ВНИМАНИЕ: Будет активировано жёлтое мигание на 1 минуту!"
echo "⚠️  Визуально контролируйте контроллер!"
echo ""
echo "Начинаем активацию через 3 секунды..."
sleep 3
# Автоматическое продолжение (раскомментируйте для интерактивного режима):
# read -p "Нажмите Enter для начала активации или Ctrl+C для отмены..."

# Функция отправки команды включения
send_yf_on() {
    node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
        --raw-set "1.3.6.1.4.1.13267.3.2.4.2.1.20" --value 1 --type Integer \
        --verbose 2>&1 | grep -E "(SET|success|Failed)" || true
}

# Функция отправки команды отключения
send_yf_off() {
    node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
        --raw-set "1.3.6.1.4.1.13267.3.2.4.2.1.20" --value 0 --type Integer \
        --verbose 2>&1 | grep -E "(SET|success|Failed)" || true
}

# Немедленная отправка первой команды
echo ""
echo "[0 сек] Отправка команды включения..."
send_yf_on

# Удержание команды в течение 60 секунд (отправка каждые 2 секунды)
echo ""
echo "Удержание команды (60 секунд, отправка каждые 2 секунды)..."
for i in {1..30}; do
    elapsed=$((i * 2))
    sleep 2
    
    echo -n "[$elapsed сек] Отправка #$i... "
    result=$(send_yf_on)
    if echo "$result" | grep -q "success\|SET"; then
        echo "✓"
    else
        echo "✗"
    fi
    
    # Проверка состояния каждые 10 секунд
    if [ $((elapsed % 10)) -eq 0 ]; then
        echo "  Проверка utcReplyFR:"
        node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
            --raw-get "1.3.6.1.4.1.13267.3.2.5.1.1.36" 2>&1 | grep -E "(INTEGER|Hex-STRING)" | head -1 || echo "  Ошибка чтения"
    fi
done

echo ""
echo "=== Шаг 4: Отключение мигания ==="
echo ""

# Отключение (3 попытки)
for i in {1..3}; do
    echo "Попытка отключения #$i..."
    send_yf_off
    if [ $i -lt 3 ]; then
        sleep 2
    fi
done

echo ""
echo "=== Шаг 5: Финальная проверка ==="
echo ""

sleep 2

echo "Режим мигания (utcReplyFR):"
node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
    --raw-get "1.3.6.1.4.1.13267.3.2.5.1.1.36" 2>&1 | grep -E "(INTEGER|Hex-STRING)" | head -1 || echo "Ошибка чтения"

echo ""
echo "Текущая фаза:"
node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
    --raw-get "1.3.6.1.4.1.13267.3.2.5.1.1.3" 2>&1 | grep -E "(INTEGER|Hex-STRING)" | head -1 || echo "Ошибка чтения"

echo ""
echo "✓ Тест завершён"
echo ""
echo "Проверьте визуально:"
echo "  1. Активировалось ли жёлтое мигание?"
echo "  2. Работало ли мигание в течение 60 секунд?"
echo "  3. Отключилось ли мигание после команды отключения?"
