#!/bin/bash
# Скрипт для выкачивания всего контроллера

CONTROLLER_IP="192.168.75.150"
CONTROLLER_USER="voicelink"
CONTROLLER_PASS="piX47xQm"
BACKUP_DIR="/home/alexey/shared_vm/spectr_utmc/spectr_utmc/controller_snapshot"

echo "=== Начало резервного копирования контроллера ==="
echo "IP: $CONTROLLER_IP"
echo "User: $CONTROLLER_USER"
echo "Backup dir: $BACKUP_DIR"
echo ""

# Создаём структуру папок
mkdir -p "$BACKUP_DIR"/{etc,home,opt,usr,var,root,ros_packages,services,system_info}

# Функция для выполнения команд через SSH
ssh_cmd() {
    sshpass -p "$CONTROLLER_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$CONTROLLER_USER@$CONTROLLER_IP" "$1"
}

# Функция для копирования файлов
scp_copy() {
    sshpass -p "$CONTROLLER_PASS" scp -o StrictHostKeyChecking=no -r "$CONTROLLER_USER@$CONTROLLER_IP:$1" "$2"
}

echo "1. Получение системной информации..."
ssh_cmd "uname -a" > "$BACKUP_DIR/system_info/uname.txt"
ssh_cmd "cat /etc/os-release" > "$BACKUP_DIR/system_info/os-release.txt"
ssh_cmd "df -h" > "$BACKUP_DIR/system_info/disk_usage.txt"
ssh_cmd "free -h" > "$BACKUP_DIR/system_info/memory.txt"
ssh_cmd "ps aux" > "$BACKUP_DIR/system_info/processes.txt"
ssh_cmd "systemctl list-units --type=service --all" > "$BACKUP_DIR/services/systemctl_services.txt"
ssh_cmd "systemctl list-unit-files --type=service" > "$BACKUP_DIR/services/systemctl_unit_files.txt"

echo "2. Поиск ROS пакетов..."
ssh_cmd "find /opt -name '*.launch' -o -name 'package.xml' 2>/dev/null | head -50" > "$BACKUP_DIR/ros_packages/ros_files.txt"
ssh_cmd "ls -la /opt/ros 2>/dev/null" > "$BACKUP_DIR/ros_packages/opt_ros.txt"
ssh_cmd "ls -la ~/catkin_ws 2>/dev/null" > "$BACKUP_DIR/ros_packages/catkin_ws.txt"
ssh_cmd "env | grep ROS" > "$BACKUP_DIR/ros_packages/ros_env.txt"
ssh_cmd "which roscore rospack rosnode 2>/dev/null" > "$BACKUP_DIR/ros_packages/ros_commands.txt"

echo "3. Копирование конфигурационных файлов..."
scp_copy "/etc" "$BACKUP_DIR/etc" 2>&1 | head -20
scp_copy "/home/$CONTROLLER_USER" "$BACKUP_DIR/home" 2>&1 | head -20

echo "4. Копирование ROS workspace (если есть)..."
scp_copy "/home/$CONTROLLER_USER/catkin_ws" "$BACKUP_DIR/ros_packages/" 2>&1 | head -20
scp_copy "/opt/ros" "$BACKUP_DIR/ros_packages/" 2>&1 | head -20

echo "5. Копирование systemd сервисов..."
scp_copy "/etc/systemd/system" "$BACKUP_DIR/services/" 2>&1 | head -20

echo "6. Получение списка установленных пакетов..."
ssh_cmd "dpkg -l" > "$BACKUP_DIR/system_info/installed_packages.txt"
ssh_cmd "apt list --installed 2>/dev/null" > "$BACKUP_DIR/system_info/apt_packages.txt"

echo "7. Поиск SNMP конфигурации..."
ssh_cmd "find /etc -name '*snmp*' 2>/dev/null" > "$BACKUP_DIR/system_info/snmp_files.txt"
scp_copy "/etc/snmp" "$BACKUP_DIR/etc/" 2>&1 | head -10

echo "8. Поиск UTMC/SINTEZ конфигурации..."
ssh_cmd "find / -name '*utmc*' -o -name '*sintez*' 2>/dev/null | head -50" > "$BACKUP_DIR/system_info/utmc_files.txt"

echo "=== Резервное копирование завершено ==="
