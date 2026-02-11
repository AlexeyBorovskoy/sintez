#!/bin/bash
#
# Скрипт для тестирования жёлтого мигания
# Использование: ./test_yellow_flashing.sh
#

set -e

CONTROLLER_IP="192.168.75.150"
COMMUNITY="UTMC"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║     Тестирование жёлтого мигания (SET_YF)                 ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Контроллер: $CONTROLLER_IP"
echo "Community: $COMMUNITY"
echo ""

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Проверка текущего состояния
echo -e "${BLUE}=== Шаг 1: Проверка текущего состояния ===${NC}"
echo ""

echo "Текущий режим работы:"
snmpget -v2c -c "$COMMUNITY" "$CONTROLLER_IP" 1.3.6.1.4.1.13267.3.2.4.1 2>&1 || echo "Ошибка чтения режима"

echo ""
echo "Текущая фаза:"
snmpget -v2c -c "$COMMUNITY" "$CONTROLLER_IP" 1.3.6.1.4.1.13267.3.2.5.1.1.3 2>&1 || echo "Ошибка чтения фазы"

echo ""
echo "Режим мигания (utcReplyFR):"
snmpget -v2c -c "$COMMUNITY" "$CONTROLLER_IP" 1.3.6.1.4.1.13267.3.2.5.1.1.36 2>&1 || echo "Ошибка чтения режима мигания"

echo ""
echo -e "${YELLOW}⚠️  ВНИМАНИЕ: Следующая команда активирует жёлтое мигание на 1 минуту!${NC}"
echo -e "${YELLOW}⚠️  Визуально контролируйте контроллер во время теста!${NC}"
echo ""
read -p "Нажмите Enter для продолжения или Ctrl+C для отмены..."

echo ""
echo -e "${BLUE}=== Шаг 2: Активация жёлтого мигания ===${NC}"
echo ""
echo "Отправка команды SET_YF (будет удерживаться 60 секунд)..."
echo ""

# Используем Node.js утилиту для отправки команды
cd "$SCRIPT_DIR/../AI_reaserh" || exit 1

# Отправка команды включения мигания
echo "Команда: SET utcControlFF = 1"
node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
    --raw-set "1.3.6.1.4.1.13267.3.2.4.2.1.20" --value 1 --type Integer \
    --verbose 2>&1 | head -20

echo ""
echo -e "${GREEN}✓ Команда отправлена${NC}"
echo ""
echo -e "${YELLOW}=== Мониторинг активации (60 секунд) ===${NC}"
echo "Проверка каждые 5 секунд..."
echo ""

# Мониторинг в течение 60 секунд
for i in {1..12}; do
    elapsed=$((i * 5))
    echo -n "[$elapsed сек] "
    
    # Проверка режима мигания
    result=$(snmpget -v2c -c "$COMMUNITY" "$CONTROLLER_IP" \
        1.3.6.1.4.1.13267.3.2.5.1.1.36 2>&1 | grep -o "INTEGER: [0-9]*" | cut -d' ' -f2 || echo "error")
    
    if [ "$result" = "1" ]; then
        echo -e "${GREEN}✓ Мигание АКТИВНО (utcReplyFR=1)${NC}"
    elif [ "$result" = "0" ]; then
        echo -e "${YELLOW}○ Мигание не активировано (utcReplyFR=0)${NC}"
    else
        echo -e "${RED}✗ Ошибка чтения${NC}"
    fi
    
    # Проверка текущей фазы
    phase=$(snmpget -v2c -c "$COMMUNITY" "$CONTROLLER_IP" \
        1.3.6.1.4.1.13267.3.2.5.1.1.3 2>&1 | grep -o "Hex-STRING: [0-9A-Fa-f]*" | cut -d' ' -f2 || echo "")
    
    if [ -n "$phase" ]; then
        # Преобразование hex в фазу
        phase_num=0
        case "$phase" in
            01) phase_num=1 ;;
            02) phase_num=2 ;;
            04) phase_num=3 ;;
            08) phase_num=4 ;;
            10) phase_num=5 ;;
            20) phase_num=6 ;;
            40) phase_num=7 ;;
        esac
        echo "    Текущая фаза: $phase_num (0x$phase)"
    fi
    
    if [ $i -lt 12 ]; then
        sleep 5
    fi
done

echo ""
echo -e "${BLUE}=== Шаг 3: Отключение мигания ===${NC}"
echo ""

# Отключение мигания
echo "Команда: SET utcControlFF = 0"
node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
    --raw-set "1.3.6.1.4.1.13267.3.2.4.2.1.20" --value 0 --type Integer \
    --verbose 2>&1 | head -20

echo ""
echo "Повторная отправка отключения (для надёжности)..."
sleep 2
node utmc-tester.js --ip "$CONTROLLER_IP" --community "$COMMUNITY" \
    --raw-set "1.3.6.1.4.1.13267.3.2.4.2.1.20" --value 0 --type Integer 2>&1 | grep -E "(SET|success|Failed)" || true

echo ""
echo -e "${BLUE}=== Шаг 4: Проверка финального состояния ===${NC}"
echo ""

sleep 2

echo "Режим мигания (utcReplyFR):"
snmpget -v2c -c "$COMMUNITY" "$CONTROLLER_IP" 1.3.6.1.4.1.13267.3.2.5.1.1.36 2>&1 || echo "Ошибка чтения"

echo ""
echo "Текущая фаза:"
snmpget -v2c -c "$COMMUNITY" "$CONTROLLER_IP" 1.3.6.1.4.1.13267.3.2.5.1.1.3 2>&1 || echo "Ошибка чтения"

echo ""
echo -e "${GREEN}=== Тестирование завершено ===${NC}"
echo ""
echo "Проверьте визуально:"
echo "  1. Активировалось ли жёлтое мигание на контроллере?"
echo "  2. Отключилось ли мигание после команды отключения?"
echo "  3. Вернулся ли контроллер в обычный режим работы?"
