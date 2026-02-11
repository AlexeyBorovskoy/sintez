# Логика работы роутера iRZ для интеграции SINTEZ контроллера с АСУДД

**Дата:** 2026-02-03  
**Основано на:** существующем коде `/home/alexey/shared_vm/spectr_utmc/spectr_utmc/spectr_utmc_cpp/`

---

## Архитектура системы

```
┌─────────────────────────────────────────────────────────────┐
│                    АСУДД Сервер                             │
│  (commserver.cudd:3000 или 192.168.57.3:3364)              │
│  Протокол: Spectr-ITS (текстовый, TCP/IP)                   │
└───────────────────────┬─────────────────────────────────────┘
                        │ TCP/IP соединение
                        │ Команды: SET_PHASE, SET_YF, GET_STAT, etc.
                        │ Ответы: >O.K., >ERROR, STAT, EVENT
                        │
┌───────────────────────▼─────────────────────────────────────┐
│              Роутер iRZ (spectr_utmc_cpp)                  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  TCP Client (TcpClient)                              │  │
│  │  - Подключение к АСУДД серверу                       │  │
│  │  - Приём команд Spectr-ITS                          │  │
│  │  - Отправка ответов и событий                       │  │
│  │  - Автоматическое переподключение                   │  │
│  └──────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Spectr Protocol Parser                              │  │
│  │  - Парсинг команд (#TIME COMMAND ID PARAMS$XX)       │  │
│  │  - Проверка checksum                                 │  │
│  │  - Формирование ответов                             │  │
│  └──────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Object Manager (SpectrObject)                       │  │
│  │  - Управление состоянием контроллера                 │  │
│  │  - Преобразование команд Spectr-ITS → SNMP           │  │
│  │  - Обработка SNMP Traps → события Spectr-ITS        │  │
│  └──────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  SNMP Handler                                         │  │
│  │  - SNMP GET/SET операции                            │  │
│  │  - SNMP Trap/Inform receiver (порт 10162)           │  │
│  │  - Управление SNMP сессиями                          │  │
│  └──────────────────────────────────────────────────────┘  │
└───────────────────────┬─────────────────────────────────────┘
                        │ SNMPv2c (UDP)
                        │ Community: UTMC
                        │ Порт: 161 (GET/SET), 162 (Traps)
                        │
┌───────────────────────▼─────────────────────────────────────┐
│         Контроллер SINTEZ (192.168.75.150)                  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  SNMP Agent (snmpd + snmp_agent)                     │  │
│  │  - Обработка SNMP запросов                           │  │
│  │  - Отправка SNMP Traps при изменениях               │  │
│  └──────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Resident Process                                    │  │
│  │  - Логика управления светофором                      │  │
│  │  - Обработка фаз, переходов, мигания                │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## Основной поток данных

### 1. Инициализация роутера

**Последовательность (из main.cpp):**

1. **Загрузка конфигурации** (`config.json`):
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

2. **Создание SNMP Handler:**
   - Инициализация с community string "UTMC"
   - Запуск SNMP Trap receiver на порту 10162
   - Callback для обработки уведомлений: `processSNMPNotification`

3. **Создание TCP Client:**
   - Подключение к АСУДД серверу (host:port из конфига)
   - Callback для приёма данных: `processITSData`
   - Callback для ошибок: обработка разрывов соединения
   - Автоматическое переподключение с таймаутом `reconnectTimeout`

4. **Создание объектов контроллеров:**
   - Для каждого объекта из конфига создаётся `SpectrObject`
   - Ключ объекта: `addr` (IP адрес контроллера)
   - Каждый объект получает указатели на `SNMPHandler` и `TcpClient`
   - Создание SNMP сессии для каждого контроллера

5. **Основной цикл:**
   - Обновление состояний объектов (`updateState()`)
   - Ожидание команд и обработка событий

---

## Обработка команд от АСУДД

### Поток обработки команды SET_PHASE

**1. Приём команды от АСУДД:**
```
TCP Client получает данные → processITSData()
```

**2. Парсинг команды (SpectrProtocol::parseCommand):**
```
Входная строка: "#15:30:45 SET_PHASE 12345 2$A3\r"

Парсинг:
- Проверка префикса '#' (команда с checksum)
- Извлечение checksum из конца строки ($XX)
- Проверка checksum (алгоритм из spectr_protocol.cpp)
- Разбор: TIME="15:30:45", COMMAND="SET_PHASE", REQUEST_ID="12345", PARAMS=["2"]
- Результат: ParsedCommand { isValid=true, command="SET_PHASE", requestId="12345", params=["2"] }
```

**3. Маршрутизация к объекту:**
```
Из main.cpp: processITSData()
- Определение целевого объекта (пока используется первый объект)
- Вызов: targetObject->processCommand(parsed)
```

**4. Обработка команды в SpectrObject (processCommand):**
```
Из object_manager.cpp:
- Проверка валидности команды
- Извлечение параметра фазы: phase = stoi(params[0]) = 2
- Вызов: setPhase(requestId="12345", phase=2)
```

**5. Выполнение SNMP SET операции (setPhase):**
```
Из object_manager.cpp: setPhase()

Формирование SNMP varbinds:
1. Operation Mode:
   - OID: "1.3.6.1.4.1.13267.3.2.4.1"
   - Type: ASN_INTEGER
   - Value: "3" (remote режим)

2. Phase Control:
   - OID: "1.3.6.1.4.1.13267.3.2.4.2.1.5" (БЕЗ SCN!)
   - Type: ASN_OCTET_STR
   - Value: битовая маска = 1 << (phase - 1) = 1 << 1 = 0x02

Вызов SNMP SET:
snmpHandler_->set(config_.addr, varbinds, callback)
```

**6. SNMP операция (SNMPHandler::set):**
```
- Создание SNMP сессии для адреса (если не существует)
- Формирование SNMP PDU с varbinds
- Отправка SNMP SET запроса на контроллер
- Ожидание ответа (timeout 5-10 секунд)
- Callback с результатом (success/error)
```

**7. Формирование ответа АСУДД:**
```
Из setPhase() callback:
- Если success: return SpectrError::OK
- Если error: return SpectrError::NOT_EXEC_5

Из processCommand():
- Формирование ответа: SpectrProtocol::formatResult(error, requestId)
- Формат: "!15:30:45 >O.K. 12345\r" или "!15:30:45 >NOT_EXEC 12345\r"
- Отправка через: sendToITS() → tcpClient_->send()
```

---

## Обработка SNMP Traps от контроллера

### Поток обработки Trap

**1. Приём SNMP Trap:**
```
SNMP Trap receiver (порт 10162) → processSNMPNotification()
```

**2. Определение объекта:**
```
Из main.cpp: processSNMPNotification()
- Поиск объекта по sourceAddress (IP адрес контроллера)
- Вызов: object->processNotification(notification)
```

**3. Обработка Trap в SpectrObject (processNotification):**
```
Из object_manager.cpp: processNotification()

Анализ varbinds в Trap:
- utcReplyGn (1.3.6.1.4.1.13267.3.2.5.1.1.3) → текущая фаза
- utcReplyGn.1 (1.3.6.1.4.1.13267.3.2.5.1.1.3.1) → takt
- utcReplyFR (1.3.6.1.4.1.13267.3.2.5.1.1.36) → режим мигания
- utcType2OperationMode → режим работы

Определение изменений состояния:
- Извлечение значений из varbinds
- Сравнение с текущим состоянием (state_)
- Формирование map изменений: {"stage": 2, "regime": 3, ...}
```

**4. Обновление состояния (changeState):**
```
Из object_manager.cpp: changeState()

Обновление полей state_:
- stage, stageLen, transition → stageChanged = true
- controlSource, algorithm, plan, regime → controlSourceChanged = true

Отправка событий (если включены в eventMask_):
- Если eventMask_ & 0x10 и stageChanged:
  → sendEvent(4, [stage, stageLen, transition])
- Если eventMask_ & 0x08 и controlSourceChanged:
  → sendEvent(3, [1, controlSource, algorithm, plan, regime])
```

**5. Формирование события Spectr-ITS:**
```
Из sendEvent():
- Формат: "#TIME EVENT (counter) TYPE PARAMS...$XX\r"
- Пример: "#15:30:50 EVENT (1) 4 2 255 0$C5\r"
- Отправка через: sendToITS() → tcpClient_->send()
```

---

## Преобразование команд Spectr-ITS → SNMP

### Таблица соответствия команд

| Spectr-ITS команда | SNMP операция | OID | Тип | Значение |
|-------------------|---------------|-----|-----|----------|
| **SET_PHASE** `<phase>` | SET (2 varbinds) | `1.3.6.1.4.1.13267.3.2.4.1` | Integer | 3 (remote) |
| | | `1.3.6.1.4.1.13267.3.2.4.2.1.5` | OctetString | `1 << (phase-1)` |
| **SET_YF** | SET (2 varbinds) | `1.3.6.1.4.1.13267.3.2.4.1` | Integer | 3 (remote) |
| | | `1.3.6.1.4.1.13267.3.2.4.2.1.20` | Integer | 1 (включить) |
| **SET_OS** | SET (2 varbinds) | `1.3.6.1.4.1.13267.3.2.4.1` | Integer | 3 (remote) |
| | | `1.3.6.1.4.1.13267.3.2.4.2.1.11` | Integer | 1 (включить) |
| **SET_LOCAL** | SET (1 varbind) | `1.3.6.1.4.1.13267.3.2.4.1` | Integer | 0 (local) |
| **SET_START** | SET (2 varbinds) | `1.3.6.1.4.1.13267.3.2.4.2.1.5.5` | Integer | 1 |
| | | `1.3.6.1.4.1.13267.3.2.4.1` | Integer | 1 (standalone) |
| **GET_STAT** | GET (множественные) | `1.3.6.1.4.1.13267.3.2.5.1.1.3` | OctetString | Текущая фаза |
| | | `1.3.6.1.4.1.13267.3.2.4.1` | Integer | Режим работы |
| | | (другие OID для полного статуса) | | |

### Важные особенности преобразования

**1. Все SET команды требуют два varbind:**
- Первый: `operationMode = 3` (переключение в remote режим)
- Второй: целевой объект управления

**2. OID БЕЗ SCN:**
- В работающем коде Node.js SCN не используется в OID
- Контроллер идентифицируется только по IP адресу
- Все OID фиксированные, без дополнительных индексов

**3. Битовые маски фаз:**
- Формула: `bit_mask = 1 << (phase - 1)`
- Фаза 1 → 0x01, Фаза 2 → 0x02, Фаза 3 → 0x04, ...
- Тип данных: OctetString (1 байт)

---

## Проблема с жёлтым миганием

### Условия активации (из документации protocol.txt)

**SetAF (жёлтое мигание):**
```
"Where a condition '1' exists for a minimum of 10 seconds,
the signals shall be set to flashing amber during
a nominated stage provided that all minimum running periods have expired."
```

**Ключевые условия:**
1. **Команда должна быть активна минимум 10 секунд**
2. **"nominated stage"** - должна быть определённая фаза
3. **"all minimum running periods have expired"** - все минимальные периоды работы фаз должны истечь

### Проблема: контроллер не принимает команды во время переходных процессов

**Гипотеза:**
Контроллер может игнорировать внешние команды во время:
- Переходов между фазами (transition periods)
- Минимальных периодов работы фаз (minimum running periods)
- Обработки внутренних событий (takt changes)

**Текущая реализация (setYF):**
```cpp
SpectrError SpectrObject::setYF(const std::string& requestId) {
    // Формирование SNMP SET команды
    std::vector<SNMPVarbind> varbinds = {
        {SNMPOID::UTC_TYPE2_OPERATION_MODE, ASN_INTEGER, "3"},
        {SNMPOID::UTC_CONTROL_FF, ASN_INTEGER, "1"}
    };
    
    // Отправка команды (однократная)
    snmpHandler_->set(config_.addr, varbinds, callback);
    
    return success ? SpectrError::OK : SpectrError::NOT_EXEC_5;
}
```

**Проблема:** Команда отправляется один раз, но документация требует **минимум 10 секунд активности**.

### Рекомендуемое решение

**Логика удержания команды:**

1. **При получении SET_YF:**
   - Установить флаг активной команды мигания
   - Запустить таймер на 10+ секунд
   - Начать периодическую отправку SNMP SET (каждые 1-2 секунды)

2. **Периодическая отправка:**
   ```
   Пока флаг активен и таймер не истёк:
     - Отправить SNMP SET (operationMode=3, controlFF=1)
     - Подождать 1-2 секунды
     - Повторить
   ```

3. **Проверка состояния контроллера:**
   - Периодически читать `utcReplyGn` (текущая фаза)
   - Определять, находится ли контроллер в "nominated stage"
   - Проверять, истекли ли минимальные периоды

4. **Остановка удержания:**
   - По истечении 10+ секунд
   - При получении новой команды (SET_PHASE, SET_LOCAL)
   - При ошибке SNMP операции

**Реализация (псевдокод):**
```cpp
class SpectrObject {
    std::atomic<bool> yfActive_;
    std::thread yfHoldThread_;
    std::atomic<bool> yfStop_;
    
    void startYFHold() {
        yfActive_ = true;
        yfStop_ = false;
        
        yfHoldThread_ = std::thread([this]() {
            auto startTime = std::chrono::steady_clock::now();
            const auto holdDuration = std::chrono::seconds(15); // 15 секунд для надёжности
            
            while (!yfStop_ && 
                   (std::chrono::steady_clock::now() - startTime) < holdDuration) {
                
                // Проверка текущей фазы (опционально)
                // Если контроллер в переходном процессе, пропустить итерацию
                
                // Отправка SNMP SET
                std::vector<SNMPVarbind> varbinds = {
                    {SNMPOID::UTC_TYPE2_OPERATION_MODE, ASN_INTEGER, "3"},
                    {SNMPOID::UTC_CONTROL_FF, ASN_INTEGER, "1"}
                };
                
                snmpHandler_->set(config_.addr, varbinds, [](bool error, ...) {
                    if (error) {
                        // Логирование ошибки, но продолжаем попытки
                    }
                });
                
                // Пауза между отправками
                std::this_thread::sleep_for(std::chrono::seconds(2));
            }
            
            yfActive_ = false;
        });
    }
    
    void stopYFHold() {
        yfStop_ = true;
        if (yfHoldThread_.joinable()) {
            yfHoldThread_.join();
        }
    }
};
```

---

## Обработка GET команд

### GET_STAT

**Логика (из getStat):**
```
1. Обновление состояния: updateState()
   - Вычисление stageCounter (время с начала фазы)
   - Вычисление cycleCounter (время с начала цикла)

2. Формирование ответа:
   "STAT damage error unitsGood units powerFlags controlSource 
    algorithm plan cycleCounter stage stageLen stageCounter 
    transition regime testMode syncError dynamicFlags"

3. Отправка: formatResult(OK, requestId, statString)
```

**Источники данных:**
- `state_` - внутреннее состояние объекта
- SNMP GET операции (периодические или по запросу)
- SNMP Traps (асинхронные обновления)

### GET_REFER

**Логика (из getRefer):**
```
Формат: "REFER \"Spectr\" <id> \"<strid>\""
Пример: "REFER \"Spectr\" 10101 \"Test SINTEZ UTMC\""

Данные из config_: id, strid
```

### GET_CONFIG

**Логика (из getConfig):**
```
Если param1=0 и param2=0:
  configText = "#TxtCfg Spectr:" + strid + " "
Иначе:
  configText = "BEGIN:\nEND.\n"

Конвертация в hex: toHex(configText)
Формат ответа: "0 0 [<hex>]"
```

---

## Управление состоянием объекта

### Структура состояния (ObjectState)

```cpp
struct ObjectState {
    uint8_t damage = 0;
    uint8_t error = 0;
    uint8_t units = 0;
    uint8_t unitsGood = 0;
    uint8_t powerFlags = 0;
    uint8_t controlSource = 255;  // 1=local, 3=remote
    uint8_t algorithm = 255;
    uint8_t plan = 255;
    uint16_t cicleCounter = 0;    // секунды с начала цикла
    uint8_t stage = 255;          // текущая фаза (1-7)
    uint8_t stageLen = 255;
    uint16_t stageCounter = 0;    // секунды с начала фазы
    uint8_t transition = 0;
    uint8_t regime = 255;         // 0=off, 2=flashing, 3=red
    uint8_t testMode = 0;
    uint8_t syncError = 0;
    uint8_t dynamicFlags = 0;
};
```

### Обновление состояния

**Источники:**
1. **SNMP Traps** - асинхронные уведомления от контроллера
2. **SNMP GET** - периодические запросы состояния
3. **Внутренние вычисления** - stageCounter, cycleCounter

**Метод updateState():**
```
- Вычисление stageCounter: время с stageStartTime_
- Вычисление cycleCounter: время с cycleStartTime_
- Обновление state_.stageCounter и state_.cicleCounter
```

**Метод changeState():**
```
- Обновление полей state_ из map изменений
- Отслеживание изменений stage (для stageStartTime_)
- Отслеживание изменений controlSource, algorithm, plan, regime
- Отправка событий (если включены в eventMask_)
```

---

## Обработка ошибок

### Типы ошибок SNMP

**Обработка в SNMPHandler:**
- `noSuchName` - неверный OID → `NOT_EXEC_3`
- `badValue` - неверное значение → `BAD_PARAM`
- `genErr` - общая ошибка → `NOT_EXEC_4`
- `timeout` - таймаут → `NOT_EXEC_255` или `OFF_LINE`

### Типы ошибок Spectr-ITS

**Коды ошибок (из SpectrProtocol):**
- `>O.K.` - успех
- `>BAD_CHECK` - ошибка checksum
- `>BAD_PARAM` - неверный параметр
- `>NOT_EXEC 1-5` - ошибка выполнения
- `>OFF_LINE` - контроллер недоступен
- `>BROKEN` - соединение разорвано

### Обработка разрывов соединения

**TCP Client (tcp_client.cpp):**
```
При разрыве соединения:
1. Установка connected_ = false
2. Закрытие socket
3. Вызов errorCallback_
4. Автоматическое переподключение через reconnectTimeout_ секунд
5. В workerThread: повторная попытка connectToHost()
```

**SNMP сессии:**
```
При ошибке SNMP операции:
- Логирование ошибки
- Возврат кода ошибки в callback
- Сессия остаётся активной для повторных попыток
```

---

## Особенности реализации

### 1. Асинхронность операций

**SNMP операции:**
- Все GET/SET операции асинхронные (с callback)
- Не блокируют основной поток
- Таймауты: 5-10 секунд

**TCP операции:**
- Отправка через очередь (sendQueue_)
- Чтение в отдельном потоке (workerThread_)
- Неблокирующий режим сокета

### 2. Управление потоками

**Основные потоки:**
1. **main thread** - основной цикл, обновление состояний
2. **TCP workerThread** - обработка TCP соединения
3. **SNMP receiverThread** - приём SNMP Traps
4. **yfHoldThread** (если реализовано) - удержание команды мигания

### 3. Синхронизация

**Мьютексы:**
- `sendMutex_` в TcpClient - защита очереди отправки
- Атомарные переменные для флагов (eventCounter_, eventMask_)

### 4. Конфигурация

**Параметры из config.json:**
- `its.host` - адрес АСУДД сервера
- `its.port` - порт TCP/IP
- `its.reconnectTimeout` - таймаут переподключения (секунды)
- `community` - SNMP community string
- `objects[]` - массив объектов контроллеров

**Параметры объекта:**
- `id` - уникальный ID (10101)
- `strid` - строковый идентификатор
- `addr` - IP адрес контроллера
- `fixGroupsOrder` - фиксированный порядок групп

---

## Рекомендации по реализации удержания команды мигания

### Проблема

Контроллер не активирует жёлтое мигание при однократной отправке команды SET_YF, возможно из-за:
1. Команда должна быть активна минимум 10 секунд (из документации)
2. Контроллер игнорирует команды во время переходных процессов
3. Требуется "nominated stage" и истечение минимальных периодов

### Решение

**Добавить механизм удержания команды:**

1. **При SET_YF:**
   - Запустить фоновый поток удержания
   - Периодически отправлять SNMP SET (каждые 2 секунды)
   - Продолжать 15 секунд (с запасом)

2. **Проверка состояния:**
   - Перед отправкой проверять текущую фазу (GET utcReplyGn)
   - Если контроллер в переходном процессе, пропустить итерацию
   - Логировать все попытки и результаты

3. **Остановка удержания:**
   - По таймауту (15 секунд)
   - При новой команде (SET_PHASE, SET_LOCAL)
   - При ошибке SNMP

4. **Мониторинг:**
   - Логирование всех SNMP операций
   - Отслеживание изменений utcReplyFR (режим мигания)
   - Визуальное подтверждение активации

---

## Итоговая логика работы роутера

### Основной цикл

```
1. Инициализация:
   - Загрузка config.json
   - Создание SNMP Handler
   - Создание TCP Client
   - Создание объектов контроллеров
   - Запуск SNMP Trap receiver

2. Подключение к АСУДД:
   - TCP Client подключается к серверу
   - При разрыве - автоматическое переподключение

3. Обработка команд от АСУДД:
   - Приём данных через TCP
   - Парсинг команд Spectr-ITS
   - Маршрутизация к объекту контроллера
   - Преобразование в SNMP операции
   - Отправка SNMP запросов
   - Формирование и отправка ответов

4. Обработка событий от контроллера:
   - Приём SNMP Traps
   - Обновление состояния объекта
   - Формирование событий Spectr-ITS
   - Отправка событий в АСУДД

5. Периодические операции:
   - Обновление состояний (stageCounter, cycleCounter)
   - Удержание активных команд (SET_YF)
   - Мониторинг соединений
```

### Ключевые моменты

1. **Двунаправленная связь:**
   - Команды: АСУДД → Роутер → Контроллер (SNMP SET)
   - События: Контроллер → Роутер → АСУДД (SNMP Trap → Spectr-ITS EVENT)

2. **Асинхронность:**
   - Все операции неблокирующие
   - Callback-based архитектура
   - Многопоточность для TCP и SNMP

3. **Надёжность:**
   - Автоматическое переподключение TCP
   - Обработка ошибок SNMP
   - Логирование всех операций

4. **Проблема мигания:**
   - Требуется удержание команды минимум 10 секунд
   - Периодическая отправка SNMP SET
   - Проверка состояния контроллера перед отправкой

---

**Статус:** Логика описана на основе существующего кода  
**Следующий шаг:** Реализация механизма удержания команды SET_YF
