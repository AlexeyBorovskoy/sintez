# UTMC/UG405 SNMP Testing Toolkit

Набор инструментов для тестирования SNMP SET/GET команд на дорожных контроллерах светофоров по протоколу UG405/UTMC.

## Установка

```bash
npm install
```

## Быстрый старт

### 1. Проверка связи с контроллером

```bash
node utmc-tester.js --ip 192.168.1.100 --test
```

### 2. Сканирование UTMC дерева OID

```bash
node utmc-tester.js --ip 192.168.1.100 --scan
```

### 3. Получение текущего состояния

```bash
node utmc-tester.js --ip 192.168.1.100 --status
```

### 4. Установка фазы

```bash
node utmc-tester.js --ip 192.168.1.100 --set-phase 3
```

### 5. Полная диагностика

```bash
node diagnose.js --ip 192.168.1.100 --output report.json
```

## Использование утилиты utmc-tester.js

```
Usage: utmc-tester [options]

Options:
  -i, --ip <address>      Controller IP address (required)
  -c, --community <str>   SNMP community string (default: "UTMC")
  -s, --scn <string>      Site Control Number
  -m, --scn-mode <mode>   SCN mode: none|ascii|index|suffix|length-prefixed (default: "none")
  -t, --timeout <ms>      SNMP timeout in milliseconds (default: "5000")
  -r, --retries <n>       Number of retries (default: "1")
  -v, --verbose           Verbose output
  -l, --log-file <path>   Log file path
  --test                  Test connection
  --status                Get controller status
  --set-phase <n>         Set phase (1-7)
  --scan                  Scan UTMC OID tree
  --raw-get <oid>         Raw SNMP GET
  --raw-set <oid>         Raw SNMP SET (use with --value and --type)
  --value <value>         Value for raw SET
  --type <type>           Type for raw SET: Integer|OctetString (default: "OctetString")
  --scenarios <file>      Run scenarios from JSON file
```

## Тестирование разных гипотез формата SCN

```bash
# Гипотеза 1: Без SCN (как в рабочем коде spectr_utmc.js)
node utmc-tester.js --ip 192.168.1.100 --set-phase 3

# Гипотеза 2: С индексом .1
node utmc-tester.js --ip 192.168.1.100 --set-phase 3 --scn-mode index

# Гипотеза 3: С SCN в ASCII кодах
node utmc-tester.js --ip 192.168.1.100 --set-phase 3 --scn CO1111 --scn-mode ascii

# Гипотеза 4: С длиной + SCN
node utmc-tester.js --ip 192.168.1.100 --set-phase 3 --scn CO1111 --scn-mode length-prefixed
```

## Запуск автоматических сценариев

```bash
node utmc-tester.js --ip 192.168.1.100 --scenarios test-scenarios.json
```

## Shell-скрипт для быстрого тестирования

```bash
chmod +x test-commands.sh
./test-commands.sh 192.168.1.100 UTMC CO1111
```

## Структура OID

```
1.3.6.1.4.1.13267              # UTMC Enterprise
├── .3                          # utmcFullUTC (UG405/Type 2)
│   └── .2                      # utcObjects
│       ├── .4                  # utcControl
│       │   ├── .1              # utcType2OperationMode
│       │   └── .2.1            # utcControlEntry
│       │       ├── .5          # utcControlFn (force bits)
│       │       ├── .11         # utcControlLO (lamps)
│       │       └── .20         # utcControlFF (flash)
│       └── .5.1.1              # utcReplyEntry
│           └── .3              # utcReplyGn (current stage)
└── .4                          # utmcSimpleUTC (Type 1)
```

## Битовые маски фаз

| Фаза | Бит | Hex | Команда      |
|------|-----|-----|--------------|
| 1    | 0   | 01  | `--value 0x01` |
| 2    | 1   | 02  | `--value 0x02` |
| 3    | 2   | 04  | `--value 0x04` |
| 4    | 3   | 08  | `--value 0x08` |
| 5    | 4   | 10  | `--value 0x10` |
| 6    | 5   | 20  | `--value 0x20` |
| 7    | 6   | 40  | `--value 0x40` |

## Режимы работы контроллера

| Значение | Режим                    |
|----------|--------------------------|
| 0        | Локальное управление     |
| 3        | Удалённое управление UTC |

## Примеры raw команд

```bash
# GET текущего режима
node utmc-tester.js --ip 192.168.1.100 --raw-get "1.3.6.1.4.1.13267.3.2.4.1"

# SET режима в remote (3)
node utmc-tester.js --ip 192.168.1.100 --raw-set "1.3.6.1.4.1.13267.3.2.4.1" --value 3 --type Integer

# SET фазы 2 (hex 0x02)
node utmc-tester.js --ip 192.168.1.100 --raw-set "1.3.6.1.4.1.13267.3.2.4.2.1.5" --value 0x02 --type OctetString
```

## Типичные ошибки

- **noSuchName** — неверный OID или контроллер не поддерживает объект
- **badValue** — неверный тип или значение данных
- **genErr** — общая ошибка (проверить режим работы контроллера)
- **timeout** — нет ответа (проверить IP, порт, community)

## Важно

1. Перед SET командами убедитесь, что контроллер допускает удалённое управление
2. SNMP community для записи может отличаться от community для чтения
3. Всегда сначала выполняйте диагностику (`--scan`) для понимания структуры OID контроллера
