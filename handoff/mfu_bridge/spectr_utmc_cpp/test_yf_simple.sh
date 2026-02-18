#!/bin/bash
#
# Простой тест жёлтого мигания с удержанием команды
# Использование: ./test_yf_simple.sh
#

CONTROLLER_IP="192.168.75.150"
COMMUNITY="UTMC"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTER_DIR="$SCRIPT_DIR/../AI_reaserh"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Тест жёлтого мигания с удержанием команды (60 сек)     ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Контроллер: $CONTROLLER_IP"
echo ""

# Проверка текущего состояния
echo "=== Текущее состояние ==="
echo "Режим работы:"
cd "$TESTER_DIR" && node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" --status 2>&1 | grep -E "(Operation Mode|Current Stage)" | head -2

echo ""
echo "⚠️  ВНИМАНИЕ: Будет активировано жёлтое мигание на 1 минуту!"
echo "⚠️  Визуально контролируйте контроллер!"
echo ""
read -p "Нажмите Enter для начала теста или Ctrl+C для отмены..."

echo ""
echo "=== Активация мигания (удержание 60 секунд) ==="
echo ""

# Функция отправки команды включения
send_yf_on() {
    cd "$TESTER_DIR" && node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
        --raw-set "1.3.6.1.4.1.13267.3.2.4.1" --value 3 --type Integer \
        --raw-set "1.3.6.1.4.1.13267.3.2.4.2.1.20" --value 1 --type Integer \
        2>&1 | grep -E "(SET|success|Failed|Error)" | head -3
}

# Функция отправки команды отключения
send_yf_off() {
    cd "$TESTER_DIR" && node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
        --raw-set "1.3.6.1.4.1.13267.3.2.4.1" --value 3 --type Integer \
        --raw-set "1.3.6.1.4.1.13267.3.2.4.2.1.20" --value 0 --type Integer \
        2>&1 | grep -E "(SET|success|Failed|Error)" | head -3
}

# Функция проверки состояния мигания
check_yf_status() {
    cd "$TESTER_DIR" && node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
        --raw-get "1.3.6.1.4.1.13267.3.2.5.1.1.36" 2>&1 | grep -E "(INTEGER|Hex-STRING|value)" | head -1
}

# Немедленная отправка первой команды
echo "[0 сек] Отправка команды включения..."
result=$(send_yf_on)
if [ -n "$result" ]; then
    echo "  $result"
else
    echo "  ✓ Команда отправлена"
fi

# Удержание команды в течение 60 секунд (отправка каждые 2 секунды)
for i in {1..30}; do
    elapsed=$((i * 2))
    sleep 2
    
    echo "[$elapsed сек] Отправка команды удержания #$i..."
    result=$(send_yf_on)
    if [ -n "$result" ]; then
        if echo "$result" | grep -qE "(success|SET.*success)"; then
            echo "  ✓ Успешно"
        else
            echo "  ✗ Ошибка: $result"
        fi
    else
        echo "  ✓ Отправлено"
    fi
    
    # Проверка состояния каждые 10 секунд
    if [ $((elapsed % 10)) -eq 0 ]; then
        echo "  Проверка utcReplyFR:"
        status=$(check_yf_status)
        if [ -n "$status" ]; then
            echo "    $status"
            if echo "$status" | grep -qE "INTEGER: 1|value.*1"; then
                echo "    ✓ Мигание АКТИВНО"
            elif echo "$status" | grep -qE "INTEGER: 0|value.*0"; then
                echo "    ○ Мигание не активировано"
            fi
        else
            echo "    ✗ Ошибка чтения"
        fi
    fi
done

echo ""
echo "=== Отключение мигания ==="
echo ""

# Отключение (3 попытки)
for i in {1..3}; do
    echo "Попытка отключения #$i..."
    result=$(send_yf_off)
    if [ -n "$result" ]; then
        echo "  $result"
    else
        echo "  ✓ Команда отправлена"
    fi
    if [ $i -lt 3 ]; then
        sleep 2
    fi
done

echo ""
echo "=== Финальная проверка ==="
echo ""

sleep 2

echo "Режим мигания (utcReplyFR):"
status=$(check_yf_status)
if [ -n "$status" ]; then
    echo "  $status"
else
    echo "  ✗ Ошибка чтения"
fi

echo ""
echo "Текущее состояние контроллера:"
cd "$TESTER_DIR" && node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" --status 2>&1 | grep -E "(Operation Mode|Current Stage)" | head -2

echo ""
echo "✓ Тест завершён"
echo ""
echo "Проверьте визуально:"
echo "  1. Активировалось ли жёлтое мигание?"
echo "  2. Работало ли мигание в течение 60 секунд?"
echo "  3. Отключилось ли мигание после команды отключения?"
