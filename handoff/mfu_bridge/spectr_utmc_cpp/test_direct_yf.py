#!/usr/bin/env python3
"""
Прямой тест SET_YF на контроллере через SNMP
Тестирование без промежуточных компонентов

Пароль SSH не хранится в репозитории. Укажите его одним из способов:
- env `DK_PASS=...`
- env `DK_PASS_FILE=/path/to/file` (файл с паролем, одна строка)
- либо введите интерактивно при запуске.
"""

import getpass
import os
import pexpect
import sys
import time
from datetime import datetime

CONTROLLER_IP = "192.168.75.150"
SSH_USER = "voicelink"
COMMUNITY = "UTMC"

# OIDs
OID_OPERATION_MODE = "1.3.6.1.4.1.13267.3.2.4.1"
OID_CONTROL_FF = "1.3.6.1.4.1.13267.3.2.4.2.1.20"
OID_REPLY_FR = "1.3.6.1.4.1.13267.3.2.5.1.1.36"
OID_REPLY_GN = "1.3.6.1.4.1.13267.3.2.5.1.1.3"

MODE_NAMES = {0: "Локальный", 1: "Автономный", 2: "Мониторинг", 3: "UTC управление"}

def _read_pass_from_file(path: str) -> str:
    with open(path, "r", encoding="utf-8") as f:
        return f.read().strip("\r\n")


def get_ssh_pass() -> str:
    """
    Возвращает пароль SSH из:
    - DK_PASS_FILE (путь к файлу с паролем, 1 строка)
    - DK_PASS (значение в env)
    - интерактивного ввода (если ничего не задано)
    """
    pass_file = os.environ.get("DK_PASS_FILE", "").strip()
    if pass_file:
        p = _read_pass_from_file(pass_file)
        if not p:
            raise RuntimeError(f"DK_PASS_FILE пустой: {pass_file}")
        return p

    p = os.environ.get("DK_PASS", "")
    if p:
        return p

    return getpass.getpass(f"SSH пароль для {SSH_USER}@{CONTROLLER_IP}: ")

def ssh_command(cmd, timeout=10):
    """Выполнение команды на контроллере через SSH"""
    try:
        child = pexpect.spawn('ssh', ['-o', 'StrictHostKeyChecking=no', 
                                      '-o', 'ConnectTimeout=5',
                                      f'{SSH_USER}@{CONTROLLER_IP}'], 
                              timeout=timeout, encoding='utf-8')
        
        index = child.expect(['password:', 'voicelink@', pexpect.EOF, pexpect.TIMEOUT], timeout=5)
        if index == 0:
            child.sendline(get_ssh_pass())
            child.expect('voicelink@', timeout=10)
        elif index == 1:
            pass
        else:
            print(f"Ошибка подключения: {child.before}")
            return None
        
        child.sendline(cmd)
        child.expect('voicelink@', timeout=timeout)
        result = child.before.strip()
        child.close()
        return result
    except Exception as e:
        print(f"Ошибка выполнения команды: {e}")
        return None

def get_oid(oid):
    """Получение значения OID"""
    cmd = f"snmpget -v2c -c {COMMUNITY} -Oqv 127.0.0.1 {oid} 2>/dev/null"
    result = ssh_command(cmd)
    if result:
        lines = result.split('\n')
        for line in reversed(lines):
            line = line.strip()
            if line and not line.startswith('voicelink@') and not line.startswith('$'):
                return line
    return None

def set_oid(oid, type_val, value):
    """Установка значения OID"""
    cmd = f"snmpset -v2c -c {COMMUNITY} 127.0.0.1 {oid} {type_val} {value} 2>&1"
    result = ssh_command(cmd)
    if result:
        return "INTEGER:" in result or "=" in result
    return False

def print_header(text):
    print("\n" + "="*60)
    print(f"  {text}")
    print("="*60 + "\n")

def main():
    print("╔════════════════════════════════════════════════════════════╗")
    print("║  Прямой тест SET_YF на контроллере                        ║")
    print("╚════════════════════════════════════════════════════════════╝")
    print(f"\nКонтроллер: {CONTROLLER_IP}")
    print(f"Пользователь SSH: {SSH_USER}")
    print(f"SNMP Community: {COMMUNITY}\n")
    
    # Шаг 1: Проверка доступности
    print_header("Шаг 1: Проверка доступности контроллера")
    
    test_result = ssh_command("echo 'OK'")
    if test_result and "OK" in test_result:
        print("✓ SSH доступ к контроллеру работает")
    else:
        print("✗ SSH доступ к контроллеру не работает")
        sys.exit(1)
    
    snmp_check = ssh_command("which snmpset")
    if snmp_check and "snmpset" in snmp_check:
        print("✓ snmpget/snmpset доступны на контроллере")
    else:
        print("✗ snmpget/snmpset не найдены на контроллере")
        sys.exit(1)
    
    # Шаг 2: Проверка текущего состояния
    print_header("Шаг 2: Проверка текущего состояния контроллера")
    
    operation_mode = get_oid(OID_OPERATION_MODE)
    if operation_mode:
        mode_num = int(operation_mode) if operation_mode.isdigit() else -1
        mode_name = MODE_NAMES.get(mode_num, "Unknown")
        print(f"  Режим работы (operationMode): {operation_mode} ({mode_name})")
    else:
        print("✗ Не удалось получить режим работы")
        operation_mode = None
    
    current_phase = get_oid(OID_REPLY_GN)
    if current_phase:
        print(f"  Текущая фаза (utcReplyGn): {current_phase}")
    else:
        current_phase = None
    
    reply_fr = get_oid(OID_REPLY_FR)
    if reply_fr:
        print(f"  Режим мигания (utcReplyFR): {reply_fr}")
    else:
        reply_fr = None
    
    control_ff = get_oid(OID_CONTROL_FF)
    if control_ff:
        print(f"  Контроль мигания (utcControlFF): {control_ff}")
    else:
        control_ff = None
    
    # Шаг 3: Отправка команды SET_YF
    print_header("Шаг 3: Отправка команды SET_YF")
    print("⚠ ВНИМАНИЕ: Будет отправлена команда SET_YF!")
    print("⚠ Все светофоры на перекрёстке должны мигать жёлтым!")
    print("\nНачинаем через 3 секунды...")
    time.sleep(3)
    
    print("\nОтправка команды SET_YF...")
    print("  - operationMode = 3 (UTC Control)")
    print("  - utcControlFF = 1 (включить мигание)")
    print()
    
    success1 = set_oid(OID_OPERATION_MODE, "i", "3")
    success2 = set_oid(OID_CONTROL_FF, "i", "1")
    
    if success1 and success2:
        print("✓ Команда SET_YF отправлена успешно")
    else:
        print("✗ Ошибка отправки команды SET_YF")
        sys.exit(1)
    
    print("\nОжидание обработки команды (3 секунды)...")
    time.sleep(3)
    
    # Шаг 4: Проверка результата
    print_header("Шаг 4: Проверка результата")
    
    new_operation_mode = get_oid(OID_OPERATION_MODE)
    if new_operation_mode:
        mode_num = int(new_operation_mode) if new_operation_mode.isdigit() else -1
        mode_name = MODE_NAMES.get(mode_num, "Unknown")
        print(f"  Режим работы (operationMode): {new_operation_mode} ({mode_name})")
        if new_operation_mode == "3":
            print("✓ Режим работы установлен в UTC Control (3)")
    
    new_control_ff = get_oid(OID_CONTROL_FF)
    if new_control_ff:
        print(f"  Контроль мигания (utcControlFF): {new_control_ff}")
        if new_control_ff == "1":
            print("✓ Контроль мигания установлен (utcControlFF=1)")
    
    new_reply_fr = get_oid(OID_REPLY_FR)
    if new_reply_fr:
        print(f"  Режим мигания (utcReplyFR): {new_reply_fr}")
        if new_reply_fr == "1":
            print("\n✓✓✓ ЖЁЛТОЕ МИГАНИЕ ДОЛЖНО БЫТЬ АКТИВНО! ✓✓✓")
        else:
            print("\n⚠ Команда отправлена, но контроллер не активировал мигание")
    
    # Сводка
    print_header("Сводка результатов")
    print("До команды:")
    print(f"  operationMode: {operation_mode}")
    print(f"  utcControlFF: {control_ff}")
    print(f"  utcReplyFR: {reply_fr}")
    print()
    print("После команды:")
    print(f"  operationMode: {new_operation_mode}")
    print(f"  utcControlFF: {new_control_ff}")
    print(f"  utcReplyFR: {new_reply_fr}")
    print()
    print("ВАЖНО: Проверьте визуально на контроллере:")
    print("  - Активировалось ли жёлтое мигание всех светофоров?")
    print("  - Работает ли мигание сейчас?")
    print()

if __name__ == "__main__":
    main()
