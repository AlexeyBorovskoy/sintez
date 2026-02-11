#!/usr/bin/env python3
"""
Скрипт для полного резервного копирования контроллера через SSH
"""

import subprocess
import os
import sys

CONTROLLER_IP = "192.168.75.150"
CONTROLLER_USER = "voicelink"
CONTROLLER_PASS = "piX47xQm"
BACKUP_DIR = "/home/alexey/shared_vm/spectr_utmc/spectr_utmc/controller_snapshot"

def run_ssh_command(cmd):
    """Выполняет команду через SSH используя ssh с паролем через stdin"""
    ssh_cmd = [
        'ssh',
        '-o', 'StrictHostKeyChecking=no',
        '-o', 'ConnectTimeout=10',
        f'{CONTROLLER_USER}@{CONTROLLER_IP}',
        cmd
    ]
    
    # Используем pexpect если доступен, иначе пробуем через ssh с паролем
    try:
        import pexpect
        child = pexpect.spawn(' '.join(ssh_cmd), timeout=30, encoding='utf-8')
        child.expect(['password:', 'yes/no'], timeout=10)
        if 'yes/no' in child.before or 'yes/no' in child.after:
            child.sendline('yes')
            child.expect('password:')
        child.sendline(CONTROLLER_PASS)
        child.expect(pexpect.EOF, timeout=300)
        return child.before
    except ImportError:
        # Fallback: используем subprocess с expect через stdin
        try:
            expect_script = f'''
spawn {" ".join(ssh_cmd)}
expect {{
    "password:" {{ send "{CONTROLLER_PASS}\\r" }}
    "yes/no" {{ send "yes\\r"; exp_continue }}
}}
expect eof
'''
            result = subprocess.run(['expect'], input=expect_script, 
                                  capture_output=True, text=True, timeout=300)
            return result.stdout
        except FileNotFoundError:
            print("Ошибка: требуется pexpect или expect")
            sys.exit(1)

def scp_copy(remote_path, local_path):
    """Копирует файлы через scp"""
    scp_cmd = [
        'scp',
        '-o', 'StrictHostKeyChecking=no',
        '-r',
        f'{CONTROLLER_USER}@{CONTROLLER_IP}:{remote_path}',
        local_path
    ]
    
    try:
        import pexpect
        child = pexpect.spawn(' '.join(scp_cmd), timeout=600, encoding='utf-8')
        child.expect(['password:', 'yes/no'], timeout=10)
        if 'yes/no' in str(child.before) or 'yes/no' in str(child.after):
            child.sendline('yes')
            child.expect('password:')
        child.sendline(CONTROLLER_PASS)
        child.expect(pexpect.EOF, timeout=600)
        return True, child.before
    except ImportError:
        try:
            expect_script = f'''
spawn {" ".join(scp_cmd)}
expect {{
    "password:" {{ send "{CONTROLLER_PASS}\\r" }}
    "yes/no" {{ send "yes\\r"; exp_continue }}
}}
expect eof
'''
            result = subprocess.run(['expect'], input=expect_script,
                                  capture_output=True, text=True, timeout=600)
            return result.returncode == 0, result.stdout + result.stderr
        except FileNotFoundError:
            print("Ошибка: требуется pexpect или expect")
            return False, ""

def main():
    print("=" * 60)
    print("Резервное копирование контроллера")
    print("=" * 60)
    print(f"IP: {CONTROLLER_IP}")
    print(f"User: {CONTROLLER_USER}")
    print(f"Backup dir: {BACKUP_DIR}")
    print()
    
    # Создаём структуру папок
    os.makedirs(f"{BACKUP_DIR}/system_info", exist_ok=True)
    os.makedirs(f"{BACKUP_DIR}/ros_packages", exist_ok=True)
    os.makedirs(f"{BACKUP_DIR}/services", exist_ok=True)
    os.makedirs(f"{BACKUP_DIR}/etc", exist_ok=True)
    os.makedirs(f"{BACKUP_DIR}/home", exist_ok=True)
    
    # 1. Системная информация
    print("1. Получение системной информации...")
    commands = {
        'uname.txt': 'uname -a',
        'os-release.txt': 'cat /etc/os-release',
        'disk_usage.txt': 'df -h',
        'memory.txt': 'free -h',
        'processes.txt': 'ps aux',
        'services.txt': 'systemctl list-units --type=service --all',
        'unit_files.txt': 'systemctl list-unit-files --type=service',
        'installed_packages.txt': 'dpkg -l',
    }
    
    for filename, cmd in commands.items():
        try:
            output = run_ssh_command(cmd)
            with open(f"{BACKUP_DIR}/system_info/{filename}", 'w', encoding='utf-8') as f:
                f.write(output)
            print(f"  ✓ {filename}")
        except Exception as e:
            print(f"  ✗ {filename}: {e}")
    
    # 2. ROS информация
    print("\n2. Поиск ROS пакетов...")
    ros_commands = {
        'ros_files.txt': 'find /opt -name "*.launch" -o -name "package.xml" 2>/dev/null | head -100',
        'ros_env.txt': 'env | grep ROS',
        'ros_commands.txt': 'which roscore rospack rosnode 2>/dev/null',
        'opt_ros.txt': 'ls -la /opt/ros 2>/dev/null',
        'catkin_ws.txt': f'ls -la ~/catkin_ws 2>/dev/null',
    }
    
    for filename, cmd in ros_commands.items():
        try:
            output = run_ssh_command(cmd)
            with open(f"{BACKUP_DIR}/ros_packages/{filename}", 'w', encoding='utf-8') as f:
                f.write(output)
            print(f"  ✓ {filename}")
        except Exception as e:
            print(f"  ✗ {filename}: {e}")
    
    # 3. UTMC/SINTEZ файлы
    print("\n3. Поиск UTMC/SINTEZ конфигурации...")
    try:
        output = run_ssh_command('find / -name "*utmc*" -o -name "*sintez*" 2>/dev/null | head -100')
        with open(f"{BACKUP_DIR}/system_info/utmc_files.txt", 'w', encoding='utf-8') as f:
            f.write(output)
        print("  ✓ utmc_files.txt")
    except Exception as e:
        print(f"  ✗ utmc_files.txt: {e}")
    
    # 4. Копирование конфигурационных директорий
    print("\n4. Копирование директорий...")
    dirs_to_copy = [
        ('/etc', f'{BACKUP_DIR}/etc'),
        (f'/home/{CONTROLLER_USER}', f'{BACKUP_DIR}/home'),
    ]
    
    for remote_dir, local_dir in dirs_to_copy:
        print(f"  Копирование {remote_dir}...")
        success, output = scp_copy(remote_dir, local_dir)
        if success:
            print(f"    ✓ {remote_dir}")
        else:
            print(f"    ✗ {remote_dir}: ошибка копирования")
    
    print("\n" + "=" * 60)
    print("Резервное копирование завершено!")
    print(f"Результаты сохранены в: {BACKUP_DIR}")
    print("=" * 60)

if __name__ == '__main__':
    main()
