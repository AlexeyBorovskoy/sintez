#!/bin/bash
#
# Полный тест интеграции: АСУДД → C++ мост → Контроллер
# Имитирует реальную работу системы
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTROLLER_IP="192.168.75.150"
ASUDD_PORT="3000"
CONFIG_FILE="$SCRIPT_DIR/config_test.json"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Полный тест интеграции: АСУДД → C++ мост → Контроллер   ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $1"
}

success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# ============================================================
# Проверка конфигурации
# ============================================================

log "=== Проверка конфигурации ==="
echo ""

if [ ! -f "$CONFIG_FILE" ]; then
    error "Файл конфигурации не найден: $CONFIG_FILE"
    exit 1
fi

success "Конфигурация найдена: $CONFIG_FILE"

# Проверка, что контроллер указан в конфигурации
if ! grep -q "$CONTROLLER_IP" "$CONFIG_FILE"; then
    warning "IP контроллера ($CONTROLLER_IP) не найден в конфигурации"
    warning "Создаю тестовую конфигурацию..."
    
    cat > "$CONFIG_FILE" <<EOF
{
  "its": {
    "host": "127.0.0.1",
    "port": $ASUDD_PORT,
    "reconnectTimeout": 10
  },
  "community": "UTMC",
  "objects": [
    { "id": 10101, "strid": "Test SINTEZ UTMC", "addr": "$CONTROLLER_IP" }
  ]
}
EOF
    
    success "Тестовая конфигурация создана"
fi

echo ""

# ============================================================
# Компиляция C++ кода
# ============================================================

log "=== Компиляция C++ кода ==="
echo ""

cd "$SCRIPT_DIR" || exit 1

if [ ! -d "build" ]; then
    log "Создание директории build..."
    mkdir -p build
fi

cd build || exit 1

if [ ! -f "CMakeCache.txt" ]; then
    log "Запуск CMake..."
    cmake .. || {
        error "Ошибка CMake"
        exit 1
    }
fi

log "Компиляция..."
make -j$(nproc) || {
    error "Ошибка компиляции"
    exit 1
}

if [ ! -f "spectr_utmc_cpp" ]; then
    error "Исполняемый файл не найден"
    exit 1
fi

success "Компиляция завершена успешно"

echo ""

# ============================================================
# Запуск тестового АСУДД сервера
# ============================================================

log "=== Запуск тестового АСУДД сервера ==="
echo ""

# Проверка, запущен ли уже сервер
if lsof -Pi :$ASUDD_PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
    warning "Порт $ASUDD_PORT уже занят. Предполагаю, что АСУДД сервер уже запущен"
else
    log "Запуск тестового АСУДД сервера на порту $ASUDD_PORT..."
    python3 "$SCRIPT_DIR/test_asudd_server.py" start &
    ASUDD_PID=$!
    sleep 2
    
    if ! kill -0 $ASUDD_PID 2>/dev/null; then
        error "Не удалось запустить тестовый АСУДД сервер"
        exit 1
    fi
    
    success "Тестовый АСУДД сервер запущен (PID: $ASUDD_PID)"
fi

echo ""

# ============================================================
# Запуск C++ моста
# ============================================================

log "=== Запуск C++ моста ==="
echo ""

log "Запуск spectr_utmc_cpp..."
cd "$SCRIPT_DIR/build" || exit 1

./spectr_utmc_cpp "$CONFIG_FILE" &
BRIDGE_PID=$!

sleep 3

if ! kill -0 $BRIDGE_PID 2>/dev/null; then
    error "Не удалось запустить C++ мост"
    exit 1
fi

success "C++ мост запущен (PID: $BRIDGE_PID)"

echo ""

# ============================================================
# Отправка команды SET_YF
# ============================================================

log "=== Отправка команды SET_YF ==="
echo ""
warning "⚠️  ВНИМАНИЕ: Будет отправлена команда SET_YF!"
warning "⚠️  Все светофоры на перекрёстке должны мигать жёлтым!"
warning "⚠️  Визуально контролируйте контроллер!"
echo ""
log "Начинаем через 3 секунды..."
sleep 3

# Отправка команды через тестовый АСУДД сервер
log "Отправка команды SET_YF через АСУДД сервер..."

# Подключение к серверу и отправка команды
REQUEST_ID="TEST$(date +%s)"
TIME_STR=$(date +%H:%M:%S)

# Вычисление checksum (упрощённая версия)
CMD_DATA="#${TIME_STR} SET_YF ${REQUEST_ID}"
# Простой checksum для теста (в реальности используется более сложный алгоритм)
CHECKSUM="00"
FORMATTED_CMD="${CMD_DATA}\$${CHECKSUM}\r"

log "Отправка команды: ${FORMATTED_CMD}"

# Отправка через netcat или python
if command -v nc >/dev/null 2>&1; then
    echo -ne "$FORMATTED_CMD" | timeout 2 nc 127.0.0.1 $ASUDD_PORT >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        success "Команда отправлена через netcat"
    else
        warning "Ошибка отправки команды через netcat"
    fi
else
    # Использование Python для отправки команды
    python3 <<EOF
import socket
import sys
import time
from datetime import datetime

def calculate_checksum(data):
    sum_val = 0
    for c in data:
        sum_val += ord(c)
        if sum_val & 0x100:
            sum_val += 1
        if sum_val & 0x80:
            sum_val += sum_val
            sum_val += 1
        else:
            sum_val += sum_val
        sum_val &= 0xFF
    return sum_val

try:
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(2)
    sock.connect(('127.0.0.1', $ASUDD_PORT))
    
    time_str = datetime.now().strftime("%H:%M:%S")
    request_id = "$REQUEST_ID"
    data = f"#{time_str} SET_YF {request_id}"
    checksum = calculate_checksum(data)
    cmd = f"{data}\${checksum:02x}\r"
    
    sock.send(cmd.encode('utf-8'))
    sock.close()
    print("Команда отправлена успешно")
except Exception as e:
    print(f"Ошибка отправки команды: {e}")
    sys.exit(1)
EOF
    
    if [ $? -eq 0 ]; then
        success "Команда отправлена через Python"
    else
        warning "Ошибка отправки команды через Python"
    fi
fi

# Ждём обработки команды
log "Ожидание обработки команды (5 секунд)..."
sleep 5

# ============================================================
# Проверка результата
# ============================================================

log "=== Проверка результата ==="
echo ""

cd "$SCRIPT_DIR/../AI_reaserh" || exit 1

log "Проверка режима мигания (utcReplyFR)..."
FR_VALUE=$(node utmc-tester.js --ip "$CONTROLLER_IP" --community "UTMC" \
    --raw-get "1.3.6.1.4.1.13267.3.2.5.1.1.36" 2>&1 | grep -o "Value: [0-9]*" | cut -d' ' -f2 || echo "0")

if [ "$FR_VALUE" = "1" ]; then
    success "Мигание АКТИВИРОВАНО! (utcReplyFR=1)"
else
    warning "Мигание НЕ активировано (utcReplyFR=$FR_VALUE)"
fi

log "Проверка режима работы..."
FINAL_MODE=$(node utmc-tester.js --ip "$CONTROLLER_IP" --community "UTMC" --status 2>&1 | grep "Operation Mode" | grep -o "[0-9]")
MODE_NAMES=("Local" "Standalone" "Monitor" "UTC Control")
log "Финальный режим: $FINAL_MODE (${MODE_NAMES[$FINAL_MODE]})"

echo ""

# ============================================================
# Остановка сервисов
# ============================================================

log "=== Остановка сервисов ==="
echo ""

if [ -n "$BRIDGE_PID" ]; then
    log "Остановка C++ моста (PID: $BRIDGE_PID)..."
    kill $BRIDGE_PID 2>/dev/null
    wait $BRIDGE_PID 2>/dev/null
    success "C++ мост остановлен"
fi

if [ -n "$ASUDD_PID" ]; then
    log "Остановка тестового АСУДД сервера (PID: $ASUDD_PID)..."
    kill $ASUDD_PID 2>/dev/null
    wait $ASUDD_PID 2>/dev/null
    success "Тестовый АСУДД сервер остановлен"
fi

echo ""
log "=== Тест завершён ==="
echo ""
warning "ВАЖНО: Проверьте визуально на контроллере:"
echo "  - Активировалось ли жёлтое мигание всех светофоров?"
echo "  - Работает ли мигание сейчас?"
echo ""
log "Для просмотра логов C++ моста проверьте вывод процесса"
log "Для повторного запуска используйте: ./test_full_integration.sh"
