#!/bin/bash
# Упрощённый тест SET_YF через C++ bridge

set -e

if [[ -z "${DK_PASS:-}" && -z "${DK_PASS_FILE:-}" ]]; then
  echo "ОШИБКА: требуется пароль SSH для проверки состояния контроллера." >&2
  echo "Укажите DK_PASS=... или DK_PASS_FILE=/path/to/file (1 строка)." >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTROLLER_IP="192.168.75.150"
ASUDD_PORT="3000"
CONFIG_FILE="$SCRIPT_DIR/config_test.json"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Тест SET_YF через C++ bridge (упрощённая версия)          ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Очистка предыдущих процессов
echo "Очистка предыдущих процессов..."
pkill -f "test_asudd_server.py" 2>/dev/null || true
pkill -f "spectr_utmc_cpp" 2>/dev/null || true
lsof -ti:$ASUDD_PORT | xargs kill -9 2>/dev/null || true
sleep 2

# Компиляция
echo "Компиляция C++ кода..."
cd "$SCRIPT_DIR" || exit 1
./build.sh > /dev/null 2>&1
if [ ! -f "build/spectr_utmc_cpp" ]; then
    echo "Ошибка: не удалось скомпилировать C++ код"
    exit 1
fi
echo "✓ Компиляция завершена"

# Запуск АСУДД сервера
echo ""
echo "Запуск тестового АСУДД сервера..."
cd "$SCRIPT_DIR" || exit 1
python3 test_asudd_server.py start > /tmp/asudd_server.log 2>&1 &
ASUDD_PID=$!
sleep 3

if ! kill -0 $ASUDD_PID 2>/dev/null; then
    echo "Ошибка: не удалось запустить АСУДД сервер"
    cat /tmp/asudd_server.log
    exit 1
fi
echo "✓ АСУДД сервер запущен (PID: $ASUDD_PID)"

# Запуск C++ моста
echo ""
echo "Запуск C++ моста..."
cd "$SCRIPT_DIR/build" || exit 1
./spectr_utmc_cpp "$CONFIG_FILE" > /tmp/cpp_bridge.log 2>&1 &
BRIDGE_PID=$!
sleep 5

if ! kill -0 $BRIDGE_PID 2>/dev/null; then
    echo "Ошибка: не удалось запустить C++ мост"
    cat /tmp/cpp_bridge.log
    kill $ASUDD_PID 2>/dev/null
    exit 1
fi
echo "✓ C++ мост запущен (PID: $BRIDGE_PID)"
echo ""

# Проверка подключения
echo "Проверка подключения C++ моста к АСУДД серверу..."
sleep 2
if grep -q "Connected to" /tmp/cpp_bridge.log; then
    echo "✓ C++ мост подключён к АСУДД серверу"
else
    echo "⚠️  C++ мост не подключён (проверьте логи)"
fi

# Отправка команды SET_YF через Python скрипт
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  ОТПРАВКА КОМАНДЫ SET_YF                                   ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "⚠️  ВНИМАНИЕ: Будет отправлена команда SET_YF!"
echo "⚠️  Все светофоры на перекрёстке должны мигать жёлтым!"
echo ""
echo "Начинаем через 3 секунды..."
sleep 3

# Использование Python для отправки команды через test_asudd_server.py
python3 <<'PYTHON_EOF'
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
    # Подключение к АСУДД серверу
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(5)
    sock.connect(('127.0.0.1', 3000))
    print("✓ Подключён к АСУДД серверу")
    
    # Формирование команды SET_YF
    time_str = datetime.now().strftime("%H:%M:%S")
    request_id = f"TEST{int(time.time())}"
    data = f"#{time_str} SET_YF {request_id}"
    checksum = calculate_checksum(data)
    cmd = f"{data}${checksum:02x}\r"
    
    print(f"Отправка команды: {cmd.strip()}")
    sock.send(cmd.encode('utf-8'))
    
    # Ожидание ответа
    time.sleep(0.5)
    try:
        response = sock.recv(4096)
        if response:
            print(f"Ответ от сервера: {response.decode('utf-8', errors='ignore').strip()}")
    except:
        pass
    
    sock.close()
    print("✓ Команда отправлена успешно")
    
except Exception as e:
    print(f"❌ Ошибка отправки команды: {e}")
    sys.exit(1)
PYTHON_EOF

if [ $? -ne 0 ]; then
    echo "❌ Ошибка отправки команды"
    kill $BRIDGE_PID 2>/dev/null
    kill $ASUDD_PID 2>/dev/null
    exit 1
fi

# Ожидание обработки
echo ""
echo "Ожидание обработки команды (5 секунд)..."
sleep 5

# Проверка результата
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  ПРОВЕРКА РЕЗУЛЬТАТА                                       ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Проверка через SSH на контроллере
echo "Проверка состояния контроллера через SSH..."
python3 <<'PYTHON_EOF'
import pexpect
import sys
import os

try:
    dk_pass = os.environ.get("DK_PASS", "").strip()
    dk_pass_file = os.environ.get("DK_PASS_FILE", "").strip()
    if not dk_pass and dk_pass_file:
        with open(dk_pass_file, "r", encoding="utf-8") as f:
            dk_pass = f.read().strip("\r\n")
    if not dk_pass:
        raise RuntimeError("Не задан пароль SSH. Укажите DK_PASS или DK_PASS_FILE.")

    # Подключение к контроллеру
    child = pexpect.spawn('ssh', ['-o', 'StrictHostKeyChecking=no', 
                                  '-o', 'ConnectTimeout=5',
                                  'voicelink@192.168.75.150'], 
                          timeout=10, encoding='utf-8')
    
    child.expect(['password:', 'voicelink@'], timeout=5)
    if 'password' in child.before.lower() or 'password' in child.after.lower():
        child.sendline(dk_pass)
    
    child.expect('voicelink@', timeout=10)
    
    # Проверка utcReplyFR
    print("Проверка режима мигания (utcReplyFR)...")
    child.sendline('snmpget -v2c -c UTMC -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.5.1.1.36')
    child.expect('voicelink@', timeout=5)
    reply_fr = child.before.strip().split('\n')[-1].strip()
    
    if reply_fr == '1':
        print(f"✓ Мигание АКТИВИРОВАНО! (utcReplyFR=1)")
    else:
        print(f"⚠️  Мигание НЕ активировано (utcReplyFR={reply_fr})")
    
    # Проверка operationMode
    print("\nПроверка режима работы (operationMode)...")
    child.sendline('snmpget -v2c -c UTMC -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.1')
    child.expect('voicelink@', timeout=5)
    operation_mode = child.before.strip().split('\n')[-1].strip()
    
    mode_names = {0: "Local", 1: "Standalone", 2: "Monitor", 3: "UTC Control"}
    mode_name = mode_names.get(int(operation_mode) if operation_mode.isdigit() else -1, "Unknown")
    print(f"Режим работы: {operation_mode} ({mode_name})")
    
    # Проверка utcControlFF
    print("\nПроверка контроля мигания (utcControlFF)...")
    child.sendline('snmpget -v2c -c UTMC -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20')
    child.expect('voicelink@', timeout=5)
    control_ff = child.before.strip().split('\n')[-1].strip()
    
    if control_ff == '1':
        print(f"✓ Контроль мигания установлен (utcControlFF=1)")
    else:
        print(f"⚠️  Контроль мигания не установлен (utcControlFF={control_ff})")
    
    child.close()
    
except Exception as e:
    print(f"❌ Ошибка проверки: {e}")
    sys.exit(1)
PYTHON_EOF

# Остановка сервисов
echo ""
echo "Остановка сервисов..."
kill $BRIDGE_PID 2>/dev/null || true
kill $ASUDD_PID 2>/dev/null || true
sleep 2

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  ТЕСТ ЗАВЕРШЁН                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "ВАЖНО: Проверьте визуально на контроллере:"
echo "  - Активировалось ли жёлтое мигание всех светофоров?"
echo "  - Работает ли мигание сейчас?"
echo ""
echo "Логи C++ моста: /tmp/cpp_bridge.log"
echo "Логи АСУДД сервера: /tmp/asudd_server.log"
