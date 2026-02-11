#!/bin/bash
# Скрипт для скачивания файлов через scp с expect

CONTROLLER_IP="192.168.75.150"
CONTROLLER_USER="voicelink"
CONTROLLER_PASS="piX47xQm"
BACKUP_DIR="/home/alexey/shared_vm/spectr_utmc/spectr_utmc/controller_snapshot"

mkdir -p "$BACKUP_DIR"/{etc,home,opt,usr,var,root,ros_packages,services,system_info,tmp_backup}

# Используем expect для scp
expect << EOF
set timeout 300
spawn scp -o StrictHostKeyChecking=no -r $CONTROLLER_USER@$CONTROLLER_IP:/tmp/backup_script $BACKUP_DIR/tmp_backup/
expect {
    "password:" {
        send "$CONTROLLER_PASS\r"
    }
    "yes/no" {
        send "yes\r"
        expect "password:"
        send "$CONTROLLER_PASS\r"
    }
}
expect eof
EOF

echo "Файлы из /tmp/backup_script скопированы"

# Копируем основные директории
for dir in etc home opt; do
    echo "Копирование /$dir..."
    expect << EOF
    set timeout 600
    spawn scp -o StrictHostKeyChecking=no -r $CONTROLLER_USER@$CONTROLLER_IP:/$dir $BACKUP_DIR/
    expect {
        "password:" {
            send "$CONTROLLER_PASS\r"
        }
    }
    expect eof
EOF
done
