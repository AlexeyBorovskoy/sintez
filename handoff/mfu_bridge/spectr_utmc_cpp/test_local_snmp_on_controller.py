#!/usr/bin/env python3
"""
Тест отправки команды SET_YF через локальный SNMP на контроллере
Проверяет гипотезу: контроллер принимает команды только от локального сервиса (127.0.0.1)

Пароль SSH не хранится в репозитории. Укажите его одним из способов:
- env `DK_PASS=...`
- env `DK_PASS_FILE=/path/to/file` (файл с паролем, одна строка)
- либо введите интерактивно при запуске.
"""

import getpass
import os
import subprocess
import sys
import time

CONTROLLER_IP = "192.168.75.150"
SSH_USER = "voicelink"


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

def run_ssh_command(command):
    """Выполнение команды через SSH с автоматическим вводом пароля"""
    try:
        import pexpect
        
        print(f"Подключение к {SSH_USER}@{CONTROLLER_IP}...")
        child = pexpect.spawn(f'ssh -o StrictHostKeyChecking=no {SSH_USER}@{CONTROLLER_IP}', 
                             encoding='utf-8', timeout=10)
        
        child.expect(['password:', 'Password:'], timeout=5)
        child.sendline(get_ssh_pass())
        
        child.expect(['\$', '#', '>'], timeout=5)
        print("✓ Подключено успешно")
        
        # Выполнение команды
        child.sendline(command)
        index = child.expect(['\$', '#', '>', pexpect.EOF, pexpect.TIMEOUT], timeout=15)
        
        # Получаем весь вывод до промпта
        output = child.before
        if index == 4:  # TIMEOUT
            output += child.read()
        
        child.sendline('exit')
        child.expect(pexpect.EOF, timeout=5)
        
        return output
        
    except ImportError:
        print("ОШИБКА: не установлен модуль pexpect.")
        print("Установите его в вашей системе и повторите запуск.")
        print("Пример (Ubuntu/Debian): sudo apt-get install python3-pexpect")
        return None
    except Exception as e:
        print(f"Ошибка SSH: {e}")
        return None

def test_local_snmp():
    """Тест локального SNMP на контроллере"""
    
    print("="*80)
    print("Тест отправки команды SET_YF через локальный SNMP на контроллере")
    print("="*80)
    print()
    
    # Команда для проверки наличия snmpset
    check_cmd = "which snmpset || echo 'snmpset не найден'"
    print("1. Проверка наличия snmpset...")
    result = run_ssh_command(check_cmd)
    if result:
        print(result)
    
    print()
    print("2. Отправка команды SET_YF через локальный SNMP (127.0.0.1)...")
    print("   Команда: snmpset -v2c -c UTMC 127.0.0.1 \\")
    print("            1.3.6.1.4.1.13267.3.2.4.1 i 3 \\")
    print("            1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1")
    print()
    
    set_yf_cmd = (
        "snmpset -v2c -c UTMC 127.0.0.1 "
        "1.3.6.1.4.1.13267.3.2.4.1 i 3 "
        "1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 2>&1"
    )
    
    result = run_ssh_command(set_yf_cmd)
    if result:
        print(result)
        if "SNMPv2-SMI" in result or "=" in result:
            print("✓ Команда выполнена успешно!")
        else:
            print("⚠ Команда выполнена, но результат неясен")
    
    print()
    print("3. Ожидание 5 секунд...")
    time.sleep(5)
    
    print()
    print("4. Проверка результата (utcReplyFR)...")
    check_cmd = (
        "snmpget -v2c -c UTMC 127.0.0.1 "
        "1.3.6.1.4.1.13267.3.2.5.1.1.36 2>&1"
    )
    
    result = run_ssh_command(check_cmd)
    if result:
        print(result)
        if "= 1" in result or "Value: 1" in result:
            print("✓ Мигание АКТИВИРОВАНО! (utcReplyFR=1)")
        else:
            print("⚠ Мигание не активировано (utcReplyFR=0 или не определено)")
    
    print()
    print("5. Отключение мигания...")
    disable_cmd = (
        "snmpset -v2c -c UTMC 127.0.0.1 "
        "1.3.6.1.4.1.13267.3.2.4.2.1.20 i 0 2>&1"
    )
    
    result = run_ssh_command(disable_cmd)
    if result:
        print(result)
    
    print()
    print("="*80)
    print("Тест завершён")
    print("="*80)
    print()
    print("ВАЖНО: Проверьте визуально на контроллере:")
    print("  - Активировалось ли жёлтое мигание всех светофоров?")
    print("  - Работало ли мигание во время теста?")

if __name__ == "__main__":
    test_local_snmp()
