# Инструкция по развертыванию на сервере

## Подготовка к развертыванию

### 1. Установка зависимостей на сервере

```bash
sudo apt-get update
sudo apt-get install -y build-essential cmake libnetsnmp-dev
```

### 2. Передача файлов на сервер

Скопируйте всю папку `spectr_utmc_cpp` на сервер:

```bash
# С сервера разработки
scp -r spectr_utmc_cpp user@server:/path/to/destination/

# Или через rsync
rsync -avz spectr_utmc_cpp/ user@server:/path/to/destination/spectr_utmc_cpp/
```

### 3. Сборка на сервере

```bash
cd /path/to/spectr_utmc_cpp
./build.sh
```

Или вручную:

```bash
cd /path/to/spectr_utmc_cpp
mkdir build && cd build
cmake ..
make
```

### 4. Настройка конфигурации

Отредактируйте `config.json`:

```bash
nano config.json
```

Убедитесь, что указаны правильные:
- ITS сервер (host и port)
- Community для SNMP
- Адреса контроллеров

### 5. Установка исполняемого файла

```bash
sudo cp build/spectr_utmc_cpp /usr/local/bin/
sudo chmod +x /usr/local/bin/spectr_utmc_cpp
```

### 6. Настройка systemd service

```bash
# Скопируйте service файл
sudo cp spectr_utmc.service /etc/systemd/system/

# Отредактируйте пути в service файле
sudo nano /etc/systemd/system/spectr_utmc.service

# Обновите пути:
# ExecStart=/usr/local/bin/spectr_utmc_cpp /etc/spectr_utmc/config.json
# WorkingDirectory=/etc/spectr_utmc

# Создайте директорию для конфигурации
sudo mkdir -p /etc/spectr_utmc
sudo cp config.json /etc/spectr_utmc/

# Перезагрузите systemd
sudo systemctl daemon-reload
```

### 7. Остановка старой версии (Node.js)

```bash
sudo systemctl stop spectr_utmc
# или
sudo systemctl stop spectr-utmc
```

Проверьте, что порт 10162 свободен:

```bash
sudo netstat -tulpn | grep 10162
```

### 8. Запуск новой версии

**Тестовый запуск:**

```bash
# Запуск вручную для проверки
/usr/local/bin/spectr_utmc_cpp /etc/spectr_utmc/config.json

# Проверка логов
tail -f /var/log/syslog | grep spectr
```

**Запуск как сервис:**

```bash
sudo systemctl enable spectr_utmc.service
sudo systemctl start spectr_utmc.service
sudo systemctl status spectr_utmc.service
```

### 9. Проверка работы

```bash
# Проверка статуса
sudo systemctl status spectr_utmc.service

# Проверка логов
sudo journalctl -u spectr_utmc.service -f

# Проверка портов
sudo netstat -tulpn | grep -E "10162|3000"

# Проверка процессов
ps aux | grep spectr_utmc_cpp
```

## Откат к Node.js версии

Если нужно вернуться к старой версии:

```bash
sudo systemctl stop spectr_utmc.service
sudo systemctl disable spectr_utmc.service
sudo systemctl start spectr_utmc  # или старое имя сервиса
```

## Мониторинг

### Логи

```bash
# Systemd логи
sudo journalctl -u spectr_utmc.service -n 100

# Постоянный мониторинг
sudo journalctl -u spectr_utmc.service -f
```

### Проверка соединений

```bash
# SNMP порт
sudo netstat -tulpn | grep 10162

# TCP соединение к ITS
sudo netstat -tulpn | grep :3000
```

## Устранение проблем

### Ошибка "Address already in use"

Порт 10162 занят - остановите старую версию:

```bash
sudo lsof -i :10162
sudo kill <PID>
```

### Ошибка подключения к ITS серверу

Проверьте:
- Доступность сервера: `ping commserver.cudd`
- Порты: `telnet commserver.cudd 3000`
- Конфигурацию в config.json

### SNMP traps не приходят

Проверьте:
- Firewall: `sudo ufw status`
- SNMP community в config.json
- Логи контроллеров

## Файлы для передачи

Минимальный набор файлов для сборки на сервере:

```
spectr_utmc_cpp/
├── build.sh                 # Скрипт сборки
├── CMakeLists.txt          # CMake конфигурация
├── config.json             # Конфигурация
├── spectr_utmc.service     # Systemd service
├── include/                # Все заголовочные файлы
└── src/                    # Все исходные файлы
```

## Быстрая проверка после установки

```bash
# 1. Проверка исполняемого файла
/usr/local/bin/spectr_utmc_cpp --help 2>&1 || echo "No help, but executable exists"

# 2. Проверка конфигурации
cat /etc/spectr_utmc/config.json

# 3. Тестовый запуск (5 секунд)
timeout 5 /usr/local/bin/spectr_utmc_cpp /etc/spectr_utmc/config.json || true

# 4. Проверка сервиса
sudo systemctl status spectr_utmc.service
```
