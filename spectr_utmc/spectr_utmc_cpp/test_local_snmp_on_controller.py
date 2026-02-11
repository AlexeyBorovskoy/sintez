#!/usr/bin/env python3
"""
Тест отправки команды SET_YF через локальный SNMP на контроллере
Проверяет гипотезу: контроллер принимает команды только от локального сервиса (127.0.0.1)
"""

import subprocess
import sys
import time

CONTROLLER_IP = "192.168.75.150"
SSH_USER = "voicelink"
SSH_PASS = "piX47xQm"

def run_ssh_command(command):
    """Выполнение команды через SSH с автоматическим вводом пароля"""
    try:
        import pexpect
        
        print(f"Подключение к {SSH_USER}@{CONTROLLER_IP}...")
        child = pexpect.spawn(f'ssh -o StrictHostKeyChecking=no {SSH_USER}@{CONTROLLER_IP}', 
                             encoding='utf-8', timeout=10)
        
        child.expect(['password:', 'Password:'], timeout=5)
        child.sendline(SSH_PASS)
        
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
        print("pexpect не установлен. Установка...")
        subprocess.run([sys.executable, '-m', 'pip', 'install', '--user', 'pexpect'], 
                      check=False)
        print("Повторите запуск скрипта")
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
