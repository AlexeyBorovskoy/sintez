# Быстрый старт

## На сервере выполните:

```bash
# 1. Установка зависимостей
sudo apt-get update
sudo apt-get install -y build-essential cmake libnetsnmp-dev

# 2. Распаковка проекта (если передали архив)
cd /path/to/
tar -xzf spectr_utmc_cpp.tar.gz
cd spectr_utmc_cpp

# 3. Сборка
./build.sh

# 4. Настройка конфигурации
nano config.json  # Проверьте настройки ITS сервера и контроллеров

# 5. Тестовый запуск
cd build
./spectr_utmc_cpp ../config.json

# Если работает - остановите (Ctrl+C) и настройте как сервис:

# 6. Установка
sudo cp build/spectr_utmc_cpp /usr/local/bin/
sudo mkdir -p /etc/spectr_utmc
sudo cp config.json /etc/spectr_utmc/

# 7. Настройка systemd
sudo cp spectr_utmc.service /etc/systemd/system/
sudo nano /etc/systemd/system/spectr_utmc.service  # Проверьте пути

# 8. Остановка старой версии
sudo systemctl stop spectr_utmc  # или старое имя сервиса

# 9. Запуск новой версии
sudo systemctl daemon-reload
sudo systemctl enable spectr_utmc.service
sudo systemctl start spectr_utmc.service

# 10. Проверка
sudo systemctl status spectr_utmc.service
sudo journalctl -u spectr_utmc.service -f
```

## Проверка работы

```bash
# Статус сервиса
sudo systemctl status spectr_utmc.service

# Логи
sudo journalctl -u spectr_utmc.service -n 50

# Порты
sudo netstat -tulpn | grep -E "10162|3000"

# Процесс
ps aux | grep spectr_utmc_cpp
```

## Откат (если нужно)

```bash
sudo systemctl stop spectr_utmc.service
sudo systemctl start spectr_utmc  # старое имя
```
