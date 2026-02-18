# C++ мост Spectr-ITS <-> UTMC (Синтез)

Мост между UTMC (городское управление дорожным движением) и Spectr-ITS для интеграции светофорных контроллеров.

## Описание

Это C++ реализация моста между UTMC (SNMP) и Spectr-ITS (TCP). Приложение подключается к ITS-серверу, парсит команды Spectr (`SET_*`/`GET_*`) и выполняет управление контроллером через UTMC/SNMP, возвращая ответы в формате Spectr (`>O.K.`, `>NOT_EXEC ...` и т.п.).

Отдельно усилена логика ЖМ (жёлтое мигание): подтверждение по `utcReplyFR` и удержание `utcControlFF=1` с периодом.

## Требования

- C++17 компилятор (g++ или clang++)
- CMake 3.10+
- net-snmp библиотека (libnetsnmp-dev)
- pthread библиотека

## Установка зависимостей

### Ubuntu/Debian:
```bash
sudo apt-get update
sudo apt-get install build-essential cmake libnetsnmp-dev
```

### CentOS/RHEL:
```bash
sudo yum install gcc-c++ cmake net-snmp-devel
```

## Сборка

```bash
cd spectr_utmc_cpp
mkdir build
cd build
cmake ..
make
```

## Конфигурация

Создайте файл `config.json`:

```json
{
  "its": {
    "host": "commserver.cudd",
    "port": 3000,
    "reconnectTimeout": 10
  },
  "community": "UTMC",
  "yf": {
    "confirmTimeoutSec": 120,
    "keepPeriodMs": 2000,
    "maxHoldSec": 0
  },
  "objects": [
    {
      "id": 10101,
      "strid": "Test SINTEZ UTMC",
      "addr": "192.168.4.77",
      "siteId": "CO1111"
    }
  ]
}
```

## Запуск

```bash
./spectr_utmc_cpp config.json
```

Логи идут в stdout/stderr (удобно запускать под `systemd`/`procd`).

## Архитектура

- **config.h/cpp** - Парсинг конфигурации JSON
- **snmp_handler.h/cpp** - Обработка SNMP операций (trap'ы, GET, SET)
- **tcp_client.h/cpp** - TCP клиент с автопереподключением к ITS серверу
- **spectr_protocol.h/cpp** - Реализация протокола Spectr-ITS (контрольная сумма, форматирование команд/ответов)
- **object_manager.h/cpp** - Управление объектами контроллеров и их состояниями
- **main.cpp** - Интеграция всех компонентов

## Протоколы

### SNMP (UTMC)
- Порт: 10162 (UDP)
- Версия: SNMPv2c
- Community: настраивается в config.json
- OID: используются из UTMC MIB (1.3.6.1.4.1.13267)

### Spectr-ITS
- Протокол: TCP/IP
- Хост/порт: настраивается в config.json
- Формат: текстовые команды с контрольной суммой

## Команды SET

- `SET_PHASE <phase>` - Установка фазы (1-7)
- `SET_YF` - Включение желтого мигания
- `SET_OS` - Выключение сигналов
- `SET_LOCAL` - Переход в локальный режим
- `SET_START` - Запуск контроллера

## Команды GET

- `GET_STAT` - Получение статуса контроллера
- `GET_REFER` - Получение информации о контроллере
- `GET_CONFIG <param1> <param2>` - Получение конфигурации
- `GET_DATE` - Получение даты

## Системный сервис

Создайте файл `/etc/systemd/system/spectr-utmc-cpp.service`:

```ini
[Unit]
Description=UTMC to Spectr-ITS bridge (C++)
After=network.target

[Service]
ExecStart=/path/to/spectr_utmc_cpp /path/to/config.json
WorkingDirectory=/path/to/spectr_utmc_cpp
Type=simple
Restart=always
RestartSec=30
User=ripas
Group=ripas

[Install]
WantedBy=multi-user.target
```

Затем:
```bash
sudo systemctl daemon-reload
sudo systemctl enable spectr-utmc-cpp
sudo systemctl start spectr-utmc-cpp
```

## Логирование

Приложение выводит логи в stdout/stderr. Для перенаправления в файл используйте systemd или перенаправление:

```bash
./spectr_utmc_cpp config.json >> /var/log/spectr_utmc.log 2>&1
```

## Отладка

Для отладки SNMP trap'ов можно использовать:
```bash
snmptrapd -f -Lo -p 10162
```

Для тестирования TCP соединения:
```bash
nc -l 3000
```

## Примечания

- Приложение работает на тех же портах, что и Node.js версия
- Перед запуском убедитесь, что Node.js версия остановлена
- Проверьте доступность портов (10162 для SNMP, порт ITS сервера для TCP)
