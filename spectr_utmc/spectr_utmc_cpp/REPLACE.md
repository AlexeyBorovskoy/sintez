# Инструкция по замене Node.js версии на C++ версию

## ⚠️ ВАЖНО: Проект использует ТЕ ЖЕ настройки и порты

- **SNMP порт:** 10162 (UDP) - тот же что у оригинала
- **ITS сервер:** commserver.cudd:3000 - тот же что у оригинала  
- **Community:** UTMC - тот же что у оригинала
- **Объекты:** те же контроллеры из config.json

## Шаги замены

### 1. Подготовка на сервере

```bash
# Установка зависимостей (если еще не установлены)
sudo apt-get update
sudo apt-get install -y build-essential cmake libnetsnmp-dev
```

### 2. Остановка старой версии

```bash
# Остановка Node.js версии
sudo systemctl stop spectr_utmc

# Проверка, что процесс остановлен
ps aux | grep "spectr_utmc.js" | grep -v grep

# Проверка, что порт 10162 свободен
sudo netstat -tulpn | grep 10162
# Должно быть пусто
```

### 3. Распаковка и сборка проекта

```bash
# Распаковка (если передали архив)
cd /home/ripas/scripts/  # или куда обычно размещаете
tar -xzf spectr_utmc_cpp.tar.gz
cd spectr_utmc_cpp

# Сборка
./build.sh

# Проверка сборки
ls -lh build/spectr_utmc_cpp
```

### 4. Копирование конфигурации

```bash
# Используем ТУ ЖЕ конфигурацию что у оригинала
sudo cp /home/ripas/scripts/spectr_utmc/config.json /etc/spectr_utmc/config.json

# Или если config.json в другом месте, скопируйте оттуда
# Важно: использовать ТОЧНО тот же config.json что у оригинала!
```

### 5. Установка исполняемого файла

```bash
sudo cp build/spectr_utmc_cpp /usr/local/bin/
sudo chmod +x /usr/local/bin/spectr_utmc_cpp
```

### 6. Настройка systemd service

```bash
# Копирование service файла
sudo cp spectr_utmc.service /etc/systemd/system/

# Проверка путей в service файле
sudo nano /etc/systemd/system/spectr_utmc.service

# Убедитесь что пути правильные:
# ExecStart=/usr/local/bin/spectr_utmc_cpp /etc/spectr_utmc/config.json
# WorkingDirectory=/etc/spectr_utmc
# User=ripas
# Group=ripas

# Перезагрузка systemd
sudo systemctl daemon-reload
```

### 7. Запуск новой версии

```bash
# Включение автозапуска
sudo systemctl enable spectr_utmc.service

# Запуск
sudo systemctl start spectr_utmc.service

# Проверка статуса
sudo systemctl status spectr_utmc.service
```

### 8. Проверка работы

```bash
# Статус сервиса (должен быть active)
sudo systemctl status spectr_utmc.service

# Логи (должны показать подключение к ITS и SNMP receiver)
sudo journalctl -u spectr_utmc.service -n 50

# Проверка портов
sudo netstat -tulpn | grep -E "10162|3000"
# Должен быть:
# UDP 0.0.0.0:10162 (SNMP receiver)
# TCP соединение к commserver.cudd:3000

# Процесс
ps aux | grep spectr_utmc_cpp
```

### 9. Мониторинг

```bash
# Постоянный мониторинг логов
sudo journalctl -u spectr_utmc.service -f

# Проверка каждые 10 секунд
watch -n 10 'sudo systemctl status spectr_utmc.service | head -15'
```

## Откат к Node.js версии (если нужно)

```bash
# Остановка C++ версии
sudo systemctl stop spectr_utmc.service
sudo systemctl disable spectr_utmc.service

# Запуск старой версии
sudo systemctl start spectr_utmc  # старое имя сервиса
sudo systemctl status spectr_utmc
```

## Что проверить после запуска

1. ✅ **SNMP receiver работает**
   - Порт 10162 слушает UDP
   - В логах: "SNMP receiver started on port 10162"

2. ✅ **TCP соединение установлено**
   - В логах: "Connected to commserver.cudd:3000"
   - netstat показывает ESTABLISHED соединение

3. ✅ **Объекты созданы**
   - В логах: "Created object: Test SINTEZ UTMC"
   - Количество объектов соответствует config.json

4. ✅ **SNMP traps приходят**
   - В логах появляются: "Inform from 192.168.4.77"
   - Обрабатываются varbinds

5. ✅ **Команды работают**
   - Команды от ITS сервера обрабатываются
   - Ответы отправляются обратно

## Ожидаемые логи при запуске

```
Loaded configuration:
  ITS: commserver.cudd:3000
  Community: UTMC
  Objects: 1
Created object: Test SINTEZ UTMC (ID: 10101, Addr: 192.168.4.77)
Spectr UTMC bridge started successfully
SNMP receiver listening on port 10162
Connecting to ITS server: commserver.cudd:3000
Connecting to commserver.cudd:3000
Connected to commserver.cudd:3000
```

## Устранение проблем

### Порт 10162 занят
```bash
sudo lsof -i :10162
sudo kill <PID>
sudo systemctl start spectr_utmc.service
```

### Не подключается к ITS серверу
```bash
# Проверка доступности
ping commserver.cudd
telnet commserver.cudd 3000

# Проверка config.json
cat /etc/spectr_utmc/config.json
```

### SNMP traps не приходят
```bash
# Проверка firewall
sudo ufw status
sudo ufw allow 10162/udp

# Проверка community в config.json
grep community /etc/spectr_utmc/config.json
```

## Важные замечания

- ⚠️ **ОБЯЗАТЕЛЬНО** остановите старую версию перед запуском новой
- ⚠️ Используйте **ТОТ ЖЕ** config.json что у оригинала
- ⚠️ Порты **НЕ МЕНЯЮТСЯ** - используются те же (10162, 3000)
- ⚠️ После замены мониторьте логи первые 10-15 минут
