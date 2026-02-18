# Спецификация протокола SINTEZ UTMC для интеграции в АСУДД

**Версия:** 1.0  
**Дата:** 2026-02-03  
**Протокол:** UG405/UTMC (SINTEZ)  
**Транспорт:** SNMPv2c + TCP/IP (Spectr-ITS)

---

## 📋 Содержание

1. [Обзор протокола](#обзор-протокола)
2. [Архитектура взаимодействия](#архитектура-взаимодействия)
3. [SNMP протокол](#snmp-протокол)
4. [Протокол Spectr-ITS](#протокол-spectr-its)
5. [Структура OID](#структура-oid)
6. [Команды управления](#команды-управления)
7. [Чтение состояния](#чтение-состояния)
8. [Форматы данных](#форматы-данных)
9. [Примеры использования](#примеры-использования)
10. [Интеграция в АСУДД](#интеграция-в-асудд)

---

## Обзор протокола

### Назначение

Протокол SINTEZ UTMC предназначен для управления дорожными контроллерами светофоров через SNMP и интеграции с системами АСУДД (Автоматизированная Система Управления Дорожным Движением).

### Компоненты протокола

1. **SNMPv2c** - для управления контроллером (SET/GET операции)
2. **Spectr-ITS** - текстовый протокол для связи с сервером АСУДД
3. **SNMP Traps/Inform** - для асинхронных уведомлений о событиях

### Версии и стандарты

- **Протокол:** UG405 (UTMC Full UTC MIB Type 2)
- **SNMP:** v2c
- **MIB:** UTMC-UTMCFULLUTCTYPE2-MIB
- **Enterprise OID:** `1.3.6.1.4.1.13267` (SINTEZ)

---

## Архитектура взаимодействия

```
┌─────────────┐         SNMPv2c          ┌──────────────┐
│   АСУДД     │◄─────────────────────────►│  Контроллер  │
│   Сервер    │    (SET/GET/Traps)       │   SINTEZ     │
└─────────────┘                           └──────────────┘
      │                                          │
      │         TCP/IP (Spectr-ITS)              │
      └──────────────────────────────────────────┘
              (текстовый протокол)
```

### Роли компонентов

- **АСУДД Сервер:** Центральный сервер управления дорожным движением
- **Мост UTMC:** Промежуточное ПО, преобразующее команды Spectr-ITS в SNMP
- **Контроллер SINTEZ:** Дорожный контроллер светофора с поддержкой SNMP

---

## SNMP протокол

### Параметры подключения

- **Версия:** SNMPv2c
- **Community:** `UTMC` (по умолчанию)
- **Порт:** 161 (UDP) для GET/SET, 162 (UDP) для Traps
- **Таймаут:** 5-10 секунд
- **Повторы:** 1-2

### Важные особенности

⚠️ **SCN (Site Control Number) НЕ используется в OID!**

- Контроллер идентифицируется **только по IP-адресу**
- OID фиксированные, без дополнительных индексов
- `siteId` в конфигурации закомментирован (`//siteId`)

### Формат OID

**Базовый OID:** `1.3.6.1.4.1.13267` (UTMC Enterprise)

**Структура:**
```
1.3.6.1.4.1.13267          # UTMC Enterprise (SINTEZ)
├── .3                      # utmcFullUTC (Type 2)
│   └── .2                  # utcObjects
│       ├── .4              # utcControl (управление)
│       │   ├── .1          # utcType2OperationMode
│       │   └── .2.1        # utcControlEntry
│       │       ├── .5      # utcControlFn (фазы)
│       │       ├── .11     # utcControlLO (лампы)
│       │       └── .20     # utcControlFF (мигание)
│       └── .5.1.1          # utcReplyEntry (состояние)
│           ├── .3          # utcReplyGn (текущая фаза)
│           ├── .14         # utcReplySDn
│           ├── .15         # utcReplyMC
│           └── .36         # utcReplyFR (режим)
```

---

## Структура OID

### Базовые константы

```cpp
namespace SNMPOID {
    const std::string UTMC = "1.3.6.1.4.1.13267";
    
    // Control (управление)
    const std::string UTC_TYPE2_OPERATION_MODE = UTMC + ".3.2.4.1";
    const std::string UTC_CONTROL_ENTRY = UTMC + ".3.2.4.2.1";
    const std::string UTC_CONTROL_FN = UTC_CONTROL_ENTRY + ".5";      // Фазы
    const std::string UTC_CONTROL_LO = UTC_CONTROL_ENTRY + ".11";     // Лампы
    const std::string UTC_CONTROL_FF = UTC_CONTROL_ENTRY + ".20";      // Мигание
    
    // Reply (состояние)
    const std::string UTC_REPLY_ENTRY = UTMC + ".3.2.5.1.1";
    const std::string UTC_REPLY_GN = UTC_REPLY_ENTRY + ".3";         // Текущая фаза
    const std::string UTC_REPLY_GN_1 = UTC_REPLY_GN + ".1";         // Takt
    const std::string UTC_REPLY_FR = UTC_REPLY_ENTRY + ".36";        // Режим мигания
    const std::string UTC_REPLY_BY_EXCEPTION = UTMC + ".3.2.6.1";    // Исключения
    
    // System
    const std::string SYS_UP_TIME = "1.3.6.1.2.1.1.3.0";
    const std::string SNMP_TRAP_OID = "1.3.6.1.6.3.1.1.4.1.0";
}
```

### Полный список OID

| Назначение | OID | Тип | Описание |
|------------|-----|-----|----------|
| **Управление** |
| Operation Mode | `1.3.6.1.4.1.13267.3.2.4.1` | Integer | Режим работы (0=local, 3=remote) |
| Control Fn (Phase) | `1.3.6.1.4.1.13267.3.2.4.2.1.5` | OctetString | Установка фазы (битовая маска) |
| Control LO (Lamps) | `1.3.6.1.4.1.13267.3.2.4.2.1.11` | Integer | Управление лампами (0=off, 1=on) |
| Control FF (Flash) | `1.3.6.1.4.1.13267.3.2.4.2.1.20` | Integer | Жёлтое мигание (0=off, 1=on) |
| **Состояние** |
| Reply Gn (Stage) | `1.3.6.1.4.1.13267.3.2.5.1.1.3` | OctetString | Текущая фаза (битовая маска) |
| Reply Gn.1 (Takt) | `1.3.6.1.4.1.13267.3.2.5.1.1.3.1` | Integer | Takt (текущий такт) |
| Reply FR (Regime) | `1.3.6.1.4.1.13267.3.2.5.1.1.36` | Integer | Режим мигания (0=normal, 1=flashing) |
| Reply SDn | `1.3.6.1.4.1.13267.3.2.5.1.1.14` | Integer | Stage Demand |
| Reply MC | `1.3.6.1.4.1.13267.3.2.5.1.1.15` | Integer | Manual Control |
| Reply DF | `1.3.6.1.4.1.13267.3.2.5.1.1.45` | Integer | Lamps Off состояние |
| **Системные** |
| GetTime | `1.3.6.1.4.1.13267.3.2.3.2` | OctetString | Системное время |
| GetVersion | `1.3.6.1.4.1.13267.3.2.1.2` | OctetString | Версия ПО |

---

## Команды управления

### Общий формат SET операций

Все SET операции требуют **два varbind**:

1. **Operation Mode** = 3 (переключение в remote режим)
2. **Целевой объект управления** (фаза, мигание, лампы)

```cpp
std::vector<SNMPVarbind> varbinds = {
    {SNMPOID::UTC_TYPE2_OPERATION_MODE, ASN_INTEGER, "3"},
    {target_oid, target_type, target_value}
};
```

### 1. Установка фазы (SET_PHASE)

**OID:** `1.3.6.1.4.1.13267.3.2.4.2.1.5`  
**Тип:** OctetString  
**Формат:** Битовая маска (1 байт)

**Битовые маски фаз:**

| Фаза | Бит | Hex | Формула | Бинарное |
|------|-----|-----|---------|----------|
| 1    | 0   | 0x01 | `1 << 0` | `00000001` |
| 2    | 1   | 0x02 | `1 << 1` | `00000010` |
| 3    | 2   | 0x04 | `1 << 2` | `00000100` |
| 4    | 3   | 0x08 | `1 << 3` | `00001000` |
| 5    | 4   | 0x10 | `1 << 4` | `00010000` |
| 6    | 5   | 0x20 | `1 << 5` | `00100000` |
| 7    | 6   | 0x40 | `1 << 6` | `01000000` |

**Формула:** `value = 1 << (phase - 1)`

**Пример (фаза 2):**
```cpp
uint8_t phase = 2;
uint8_t bit_mask = 1 << (phase - 1);  // = 0x02

std::vector<SNMPVarbind> varbinds = {
    {SNMPOID::UTC_TYPE2_OPERATION_MODE, ASN_INTEGER, "3"},
    {SNMPOID::UTC_CONTROL_FN, ASN_OCTET_STR, std::string(1, bit_mask)}
};
```

**SNMP команда (snmpset):**
```bash
snmpset -v2c -c UTMC 192.168.75.150 \
  1.3.6.1.4.1.13267.3.2.4.1 i 3 \
  1.3.6.1.4.1.13267.3.2.4.2.1.5 x 02
```

### 2. Жёлтое мигание (SET_YF / SetAF)

**OID:** `1.3.6.1.4.1.13267.3.2.4.2.1.20`  
**Тип:** Integer  
**Значения:** 0 = выключено, 1 = включено

**Условия активации:**
- Команда должна быть активна минимум 10 секунд
- Должна быть "nominated stage" (номинированная фаза)
- Все минимальные периоды работы фаз должны истечь

**Пример:**
```cpp
std::vector<SNMPVarbind> varbinds = {
    {SNMPOID::UTC_TYPE2_OPERATION_MODE, ASN_INTEGER, "3"},
    {SNMPOID::UTC_CONTROL_FF, ASN_INTEGER, "1"}
};
```

**SNMP команда:**
```bash
snmpset -v2c -c UTMC 192.168.75.150 \
  1.3.6.1.4.1.13267.3.2.4.1 i 3 \
  1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1
```

### 3. Управление лампами (SET_OS / SetOFF)

**OID:** `1.3.6.1.4.1.13267.3.2.4.2.1.11`  
**Тип:** Integer  
**Значения:** 0 = выключено, 1 = включено

**Условия:**
- Команда должна быть активна минимум 10 секунд
- При значении 1: лампы включаются согласно Start Up Sequence
- При значении 0: лампы выключаются после истечения минимальных периодов

**Пример:**
```cpp
std::vector<SNMPVarbind> varbinds = {
    {SNMPOID::UTC_TYPE2_OPERATION_MODE, ASN_INTEGER, "3"},
    {SNMPOID::UTC_CONTROL_LO, ASN_INTEGER, "1"}  // Включить лампы
};
```

### 4. Возврат в локальный режим (SET_LOCAL)

**OID:** `1.3.6.1.4.1.13267.3.2.4.1`  
**Тип:** Integer  
**Значение:** 0

**Пример:**
```cpp
std::vector<SNMPVarbind> varbinds = {
    {SNMPOID::UTC_TYPE2_OPERATION_MODE, ASN_INTEGER, "0"}
};
```

### 5. Запуск контроллера (SET_START)

**Описание:** Перезапуск контроллера в нормальный режим работы

**Реализация:** Установка `UTC_CONTROL_LO = 1` (включение ламп)

---

## Чтение состояния

### 1. Текущая фаза (GetPhase)

**OID:** `1.3.6.1.4.1.13267.3.2.5.1.1.3`  
**Тип:** OctetString  
**Формат:** Битовая маска (1 или более байт)

**Обработка:**
```cpp
// Получение битовой маски
uint8_t bit_mask = reply_value[0];

// Определение фазы из битовой маски
uint8_t phase = 0;
for (int i = 0; i < 8; i++) {
    if (bit_mask & (1 << i)) {
        phase = i + 1;
        break;
    }
}
```

**SNMP команда:**
```bash
snmpget -v2c -c UTMC 192.168.75.150 1.3.6.1.4.1.13267.3.2.5.1.1.3
```

**Ответ:** `Hex-STRING: 40` (фаза 7)

### 2. Режим работы (GetMode)

**OID:** `1.3.6.1.4.1.13267.3.2.4.1`  
**Тип:** Integer

**Значения:**
- `0` - Локальное управление
- `1` - Автономный режим
- `2` - Сервисный режим
- `3` - Удалённое управление UTC

### 3. Режим мигания (GetAF)

**OID:** `1.3.6.1.4.1.13267.3.2.5.1.1.36`  
**Тип:** Integer

**Значения:**
- `0` - Нормальный режим
- `1` - Жёлтое мигание активно

**Примечание:** `UTC_CONTROL_FF` является write-only объектом (не читается)

### 4. Системное время (GetTime)

**OID:** `1.3.6.1.4.1.13267.3.2.3.2`  
**Тип:** OctetString  
**Формат:** `YYYYMMDDHHmmssZ` (GMT)

**Пример:** `20260203151200Z`

### 5. Версия ПО (GetVersion)

**OID:** `1.3.6.1.4.1.13267.3.2.1.2`  
**Тип:** OctetString  
**Формат:** Строка версии (vendor specific)

**Пример:** `V001`

---

## Форматы данных

### Типы данных SNMP

| SNMP Тип | ASN.1 Код | C++ Тип | Описание |
|----------|-----------|---------|----------|
| Integer | 2 | int32_t | Целое число |
| OctetString | 4 | std::string/Buffer | Байтовая строка |
| OID | 6 | std::string | Object Identifier |
| Counter | 65 | uint32_t | Счётчик |
| Gauge | 66 | uint32_t | Измеритель |
| TimeTicks | 67 | uint32_t | Время в сотых долях секунды |

### Битовая маска фаз

**Формат:** OctetString (1 байт)

**Интерпретация:**
- Каждый бит соответствует фазе (бит 0 = фаза 1, бит 1 = фаза 2, ...)
- Только один бит может быть установлен одновременно
- Значение `0x00` означает отсутствие активной фазы

**Примеры:**
```
0x01 = 00000001 → Фаза 1
0x02 = 00000010 → Фаза 2
0x04 = 00000100 → Фаза 3
0x40 = 01000000 → Фаза 7
```

### Режимы работы

| Значение | Режим | Описание |
|----------|-------|----------|
| 0 | Local | Локальное управление (ручное) |
| 1 | Standalone | Автономный режим (встроенные программы) |
| 2 | Service | Сервисный режим |
| 3 | Remote UTC | Удалённое управление через UTC |

---

## Протокол Spectr-ITS

### Назначение

Текстовый протокол для связи между АСУДД сервером и мостом UTMC.

### Транспорт

- **Протокол:** TCP/IP
- **Порт:** 3000-3364 (настраивается)
- **Кодировка:** UTF-8
- **Разделитель:** `\r\n`

### Формат команд

**Структура:**
```
#<timestamp> <COMMAND> <request_id> [params...]$<checksum>\r
```

**Компоненты:**
- `#` - префикс команды
- `<timestamp>` - время в формате `HH:MM:SS`
- `<COMMAND>` - имя команды (SET_PHASE, GET_STAT, etc.)
- `<request_id>` - идентификатор запроса
- `[params...]` - параметры команды (опционально)
- `$<checksum>` - контрольная сумма (2 hex символа)
- `\r` - завершающий символ

### Формат ответов

**Успешный ответ:**
```
#<timestamp> >O.K. <request_id>$<checksum>\r
```

**Ошибка:**
```
#<timestamp> >ERROR <request_id>$<checksum>\r
```

**С данными:**
```
#<timestamp> <COMMAND> <request_id> <data>$<checksum>\r
```

### Контрольная сумма

**Алгоритм:**
```cpp
uint8_t checksum(const std::string& data) {
    uint8_t sum = 0;
    for (char c : data) {
        sum += static_cast<uint8_t>(c);
        if (sum & 0x100) {
            sum = (sum & 0xFF) + 1;
        }
        sum = (sum << 1) | ((sum & 0x80) ? 1 : 0);
        sum &= 0xFF;
    }
    return sum;
}
```

### Команды протокола

#### SET команды

| Команда | Параметры | Описание |
|---------|-----------|----------|
| `SET_PHASE` | `<phase>` | Установка фазы (1-7) |
| `SET_YF` | - | Включение жёлтого мигания |
| `SET_OS` | - | Включение режима "Все выключено" |
| `SET_LOCAL` | - | Возврат в локальный режим |
| `SET_START` | - | Запуск контроллера |
| `SET_EVENT` | `<mask>` | Установка маски событий (0-65535) |

#### GET команды

| Команда | Параметры | Описание |
|---------|-----------|----------|
| `GET_STAT` | - | Получение статуса контроллера |
| `GET_REFER` | - | Получение справочной информации |
| `GET_CONFIG` | `<param1> <param2>` | Получение конфигурации |
| `GET_DATE` | - | Получение даты |

### Примеры команд

**SET_PHASE:**
```
#15:30:45 SET_PHASE 12345 2$A3\r
```

**GET_STAT:**
```
#15:30:50 GET_STAT 12346$B4\r
```

**Ответ GET_STAT:**
```
#15:30:50 STAT 12346 0 0 1 1 0 3 1 0 2 0 0 3 0 0 0$C5\r
```

**Поля ответа STAT:**
```
damage error unitsGood units powerFlags controlSource algorithm plan 
cycleCounter stage stageLen stageCounter transition regime testMode 
syncError dynamicFlags
```

---

## Примеры использования

### Пример 1: Установка фазы 3

**C++ код:**
```cpp
#include "snmp_handler.h"
#include "object_manager.h"

// Создание SNMP сессии
SNMPHandler snmp("UTMC");
snmp.createSession("192.168.75.150", "UTMC");

// Установка фазы 3
uint8_t phase = 3;
uint8_t bit_mask = 1 << (phase - 1);  // = 0x04

std::vector<SNMPVarbind> varbinds = {
    {SNMPOID::UTC_TYPE2_OPERATION_MODE, ASN_INTEGER, "3"},
    {SNMPOID::UTC_CONTROL_FN, ASN_OCTET_STR, std::string(1, bit_mask)}
};

snmp.set("192.168.75.150", varbinds, [](bool error, const std::vector<SNMPVarbind>& result) {
    if (!error) {
        std::cout << "Фаза установлена успешно" << std::endl;
    }
});
```

**SNMP команда:**
```bash
snmpset -v2c -c UTMC 192.168.75.150 \
  1.3.6.1.4.1.13267.3.2.4.1 i 3 \
  1.3.6.1.4.1.13267.3.2.4.2.1.5 x 04
```

### Пример 2: Включение жёлтого мигания

**C++ код:**
```cpp
std::vector<SNMPVarbind> varbinds = {
    {SNMPOID::UTC_TYPE2_OPERATION_MODE, ASN_INTEGER, "3"},
    {SNMPOID::UTC_CONTROL_FF, ASN_INTEGER, "1"}
};

snmp.set("192.168.75.150", varbinds, [](bool error, const std::vector<SNMPVarbind>& result) {
    if (!error) {
        std::cout << "Жёлтое мигание включено" << std::endl;
        // Удерживать команду минимум 10 секунд
    }
});
```

### Пример 3: Чтение текущей фазы

**C++ код:**
```cpp
std::vector<std::string> oids = {
    SNMPOID::UTC_REPLY_GN
};

snmp.get("192.168.75.150", oids, [](bool error, const std::vector<SNMPVarbind>& result) {
    if (!error && !result.empty()) {
        uint8_t bit_mask = static_cast<uint8_t>(result[0].value[0]);
        uint8_t phase = 0;
        for (int i = 0; i < 8; i++) {
            if (bit_mask & (1 << i)) {
                phase = i + 1;
                break;
            }
        }
        std::cout << "Текущая фаза: " << (int)phase << std::endl;
    }
});
```

### Пример 4: Обработка SNMP Trap

**C++ код:**
```cpp
snmp.startReceiver(162, [](const SNMPNotification& notification) {
    std::cout << "Trap от " << notification.sourceAddress << std::endl;
    
    for (const auto& varbind : notification.varbinds) {
        if (varbind.oid == SNMPOID::UTC_REPLY_GN) {
            // Обработка изменения фазы
            uint8_t bit_mask = static_cast<uint8_t>(varbind.value[0]);
            // ... определение фазы
        }
    }
});
```

---

## Интеграция в АСУДД

### Архитектура интеграции

```
┌─────────────────────────────────────────────────────────┐
│                    АСУДД Сервер                         │
│  ┌──────────────────────────────────────────────────┐   │
│  │         Протокол Spectr-ITS                      │   │
│  │  (TCP/IP, текстовые команды)                     │   │
│  └──────────────────────────────────────────────────┘   │
└───────────────────────┬─────────────────────────────────┘
                        │ TCP/IP
                        │
┌───────────────────────▼─────────────────────────────────┐
│              Мост UTMC (spectr_utmc_cpp)               │
│  ┌──────────────────┐      ┌──────────────────────┐   │
│  │  Spectr-ITS      │      │   SNMP Handler       │   │
│  │  Protocol        │◄────►│   (SET/GET/Traps)    │   │
│  └──────────────────┘      └──────────────────────┘   │
└───────────────────────┬─────────────────────────────────┘
                        │ SNMPv2c
                        │
┌───────────────────────▼─────────────────────────────────┐
│         Контроллер SINTEZ (192.168.75.150)             │
│  ┌──────────────────────────────────────────────────┐   │
│  │  SNMP Agent (snmpd + snmp_agent)                │   │
│  │  Resident Process (логика светофора)            │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

### Компоненты моста UTMC

1. **TCP/IP Сервер** - приём команд от АСУДД
2. **Парсер Spectr-ITS** - разбор текстовых команд
3. **SNMP Handler** - выполнение SNMP операций
4. **Trap Receiver** - приём асинхронных уведомлений
5. **Object Manager** - управление объектами контроллеров

### Конфигурация

**config.json:**
```json
{
  "its": {
    "host": "commserver.cudd",
    "port": 3000,
    "reconnectTimeout": 10
  },
  "community": "UTMC",
  "objects": [
    {
      "id": 10101,
      "strid": "Test SINTEZ UTMC",
      "addr": "192.168.75.150",
      "fixGroupsOrder": true
    }
  ]
}
```

**Параметры:**
- `its.host` - адрес АСУДД сервера
- `its.port` - порт TCP/IP соединения
- `community` - SNMP community string
- `objects[].id` - уникальный ID объекта
- `objects[].strid` - строковый идентификатор
- `objects[].addr` - IP адрес контроллера
- `objects[].fixGroupsOrder` - фиксированный порядок групп

### Последовательность операций

#### 1. Инициализация

```cpp
// Загрузка конфигурации
Config config("config.json");

// Создание SNMP handler
SNMPHandler snmpHandler(config.community);

// Создание TCP/IP клиента
TcpClient tcpClient(config.its.host, config.its.port);

// Создание объектов для каждого контроллера
for (const auto& objConfig : config.objects) {
    auto obj = std::make_unique<SpectrObject>(
        objConfig, &snmpHandler, &tcpClient
    );
    objects_[objConfig.addr] = std::move(obj);
}
```

#### 2. Обработка команды SET_PHASE

```
АСУДД → Мост:  #15:30:45 SET_PHASE 12345 2$A3\r
Мост → SNMP:   SET operationMode=3, controlFn=0x02
SNMP → Контроллер: SET запрос
Контроллер → SNMP: SET Response (успех)
Мост → АСУДД:  #15:30:45 >O.K. 12345$B4\r
```

#### 3. Обработка события (Trap)

```
Контроллер → SNMP: Trap (изменение фазы)
SNMP → Мост:  Notification (utcReplyGn)
Мост → АСУДД: #15:30:50 EVENT (1) 4 2 0 0$C5\r
```

### Обработка ошибок

**Типы ошибок SNMP:**
- `noSuchName` - неверный OID
- `badValue` - неверное значение
- `genErr` - общая ошибка
- `timeout` - таймаут соединения

**Коды ошибок Spectr-ITS:**
- `>O.K.` - успех
- `>BAD_CHECK` - ошибка контрольной суммы
- `>BAD_PARAM` - неверный параметр
- `>NOT_EXEC 1-5` - ошибка выполнения
- `>OFF_LINE` - контроллер недоступен

### Рекомендации по реализации

1. **Таймауты:**
   - SNMP операции: 5-10 секунд
   - TCP/IP соединение: 30 секунд
   - Переподключение: 10 секунд

2. **Повторы:**
   - SNMP GET: 1-2 повтора
   - SNMP SET: 1 повтора (осторожно!)
   - TCP/IP: автоматическое переподключение

3. **Буферизация:**
   - Команды от АСУДД: очередь на обработку
   - SNMP Traps: асинхронная обработка
   - Состояние контроллеров: кэширование

4. **Логирование:**
   - Все SNMP операции
   - Все команды Spectr-ITS
   - Ошибки и исключения
   - Изменения состояния

5. **Безопасность:**
   - Валидация всех входных данных
   - Проверка контрольных сумм
   - Ограничение частоты команд
   - Мониторинг состояния соединений

---

## Приложение A: Таблица соответствия команд

| Spectr-ITS | SNMP OID | Тип | Значение |
|------------|----------|-----|----------|
| SET_PHASE | `1.3.6.1.4.1.13267.3.2.4.2.1.5` | OctetString | Битовая маска |
| SET_YF | `1.3.6.1.4.1.13267.3.2.4.2.1.20` | Integer | 1 |
| SET_OS | `1.3.6.1.4.1.13267.3.2.4.2.1.11` | Integer | 1 |
| SET_LOCAL | `1.3.6.1.4.1.13267.3.2.4.1` | Integer | 0 |
| GET_STAT | `1.3.6.1.4.1.13267.3.2.5.1.1.3` | OctetString | Текущая фаза |

---

## Приложение B: Коды ошибок

| Код | Описание |
|-----|----------|
| `>O.K.` | Успешное выполнение |
| `>BAD_CHECK` | Ошибка контрольной суммы |
| `>BAD_PARAM` | Неверный параметр |
| `>NOT_EXEC 1` | Нет приоритета |
| `>NOT_EXEC 2` | Неверные параметры |
| `>NOT_EXEC 3` | Неверная команда |
| `>NOT_EXEC 4` | Выполнение невозможно |
| `>NOT_EXEC 5` | Внутренняя ошибка |
| `>OFF_LINE` | Контроллер недоступен |
| `>BROKEN` | Соединение разорвано |

---

## Приложение C: Ссылки на документацию

1. **MIB файлы:**
   - `UTMC-UTMCFULLUTCTYPE2-MIB.txt` - полное описание MIB
   - `Sintez_snmp_protocols.xlsx` - таблица OID

2. **Протоколы:**
   - `protocol.txt` - описание протокола UG405
   - RFC 2578 - SNMPv2 MIB структура

3. **Реализация:**
   - `spectr_utmc_cpp/` - C++ реализация моста
   - `controller_snapshot/` - слепок рабочего контроллера

---

**Версия документа:** 1.0  
**Дата:** 2026-02-03  
**Статус:** Готово к использованию
