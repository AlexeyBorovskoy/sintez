# Упрощённая реализация SET_YF (точное копирование Node.js логики)

**Дата:** 2026-02-04  
**Цель:** Создать упрощённую версию `setYF`, которая точно копирует логику Node.js кода

---

## Анализ Node.js кода

### Оригинальная реализация:
```javascript
SET_YF(e){
    return this.set(e,[
        {oid:l.utcType2OperationMode,type:u,value:3},
        {oid:l.utcControlFF,type:u,value:1}
    ])
}
```

### Ключевые особенности:
1. **Однократная отправка** - команда отправляется один раз
2. **Нет проверок** - не проверяет режим, фазу, время
3. **Нет удержания** - команда не повторяется
4. **Две команды в одной транзакции** - обе SNMP SET команды отправляются одновременно

---

## Текущая C++ реализация (сложная)

Текущая реализация делает:
1. Проверку текущего режима работы
2. Перевод в режим UTC Control (если необходимо)
3. Проверку текущей фазы
4. Установку специальной фазы (если необходимо)
5. Ожидание минимального периода работы фазы
6. Отправку команды SET_YF
7. Запуск механизма удержания команды

**Проблема:** Это слишком сложно и не соответствует оригинальному Node.js коду.

---

## Упрощённая C++ реализация (точное копирование)

### Вариант 1: Полное упрощение (рекомендуется для тестирования)

```cpp
SpectrError SpectrObject::setYF(const std::string& requestId) {
    if (!snmpHandler_) {
        return SpectrError::NOT_EXEC_5;
    }
    
    // Точное копирование Node.js логики - просто отправляем две команды один раз
    std::vector<SNMPVarbind> varbinds;
    
    SNMPVarbind modeVarbind;
    modeVarbind.oid = SNMPOID::UTC_TYPE2_OPERATION_MODE;
    modeVarbind.type = ASN_INTEGER;
    modeVarbind.value = "3";
    varbinds.push_back(modeVarbind);
    
    SNMPVarbind ffVarbind;
    ffVarbind.oid = SNMPOID::UTC_CONTROL_FF;
    ffVarbind.type = ASN_INTEGER;
    ffVarbind.value = "1";
    varbinds.push_back(ffVarbind);
    
    bool success = false;
    snmpHandler_->set(config_.addr, varbinds, [&success, requestId, this](bool error, const std::vector<SNMPVarbind>&) {
        success = !error;
        // Отправка ответа ASUDD (как в Node.js коде)
        if (tcpClient_ && tcpClient_->isConnected()) {
            SpectrError result = error ? SpectrError::NOT_EXEC_5 : SpectrError::OK;
            std::string response = protocol_.formatResult(result, requestId);
            tcpClient_->send(response);
        }
    });
    
    // Ожидание результата (с таймаутом)
    auto startWait = std::chrono::steady_clock::now();
    while (!success && 
           (std::chrono::steady_clock::now() - startWait) < std::chrono::seconds(2)) {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
    
    return success ? SpectrError::OK : SpectrError::NOT_EXEC_5;
}
```

### Вариант 2: С минимальной проверкой режима (компромисс)

```cpp
SpectrError SpectrObject::setYF(const std::string& requestId) {
    if (!snmpHandler_) {
        return SpectrError::NOT_EXEC_5;
    }
    
    // Остановка удержания, если активно
    if (yfHoldActive_) {
        stopYFHold();
    }
    
    // Простая проверка режима (без ожидания)
    std::vector<std::string> oids = {SNMPOID::UTC_TYPE2_OPERATION_MODE};
    uint8_t currentMode = 3; // По умолчанию UTC Control
    
    snmpHandler_->get(config_.addr, oids, [&currentMode](bool error, const std::vector<SNMPVarbind>& varbinds) {
        if (!error && !varbinds.empty()) {
            try {
                currentMode = static_cast<uint8_t>(std::stoi(varbinds[0].value));
            } catch (...) {
                currentMode = 3;
            }
        }
    });
    
    // Небольшая пауза для получения режима
    std::this_thread::sleep_for(std::chrono::milliseconds(200));
    
    // Если режим не UTC Control, сначала переводим в UTC Control
    if (currentMode != 3) {
        std::vector<SNMPVarbind> modeVarbinds;
        SNMPVarbind modeVarbind;
        modeVarbind.oid = SNMPOID::UTC_TYPE2_OPERATION_MODE;
        modeVarbind.type = ASN_INTEGER;
        modeVarbind.value = "3";
        modeVarbinds.push_back(modeVarbind);
        
        bool modeSet = false;
        snmpHandler_->set(config_.addr, modeVarbinds, [&modeSet](bool error, const std::vector<SNMPVarbind>&) {
            modeSet = !error;
        });
        
        // Ожидание установки режима
        auto startWait = std::chrono::steady_clock::now();
        while (!modeSet && 
               (std::chrono::steady_clock::now() - startWait) < std::chrono::seconds(1)) {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }
        
        // Небольшая пауза для стабилизации
        std::this_thread::sleep_for(std::chrono::milliseconds(500));
    }
    
    // Отправка команды SET_YF (как в Node.js коде)
    std::vector<SNMPVarbind> varbinds;
    
    SNMPVarbind modeVarbind;
    modeVarbind.oid = SNMPOID::UTC_TYPE2_OPERATION_MODE;
    modeVarbind.type = ASN_INTEGER;
    modeVarbind.value = "3";
    varbinds.push_back(modeVarbind);
    
    SNMPVarbind ffVarbind;
    ffVarbind.oid = SNMPOID::UTC_CONTROL_FF;
    ffVarbind.type = ASN_INTEGER;
    ffVarbind.value = "1";
    varbinds.push_back(ffVarbind);
    
    bool success = false;
    snmpHandler_->set(config_.addr, varbinds, [&success, requestId, this](bool error, const std::vector<SNMPVarbind>&) {
        success = !error;
        // Отправка ответа ASUDD
        if (tcpClient_ && tcpClient_->isConnected()) {
            SpectrError result = error ? SpectrError::NOT_EXEC_5 : SpectrError::OK;
            std::string response = protocol_.formatResult(result, requestId);
            tcpClient_->send(response);
        }
    });
    
    // Ожидание результата
    auto startWait = std::chrono::steady_clock::now();
    while (!success && 
           (std::chrono::steady_clock::now() - startWait) < std::chrono::seconds(2)) {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
    
    return success ? SpectrError::OK : SpectrError::NOT_EXEC_5;
}
```

---

## Рекомендации

### Для тестирования:
1. **Использовать Вариант 1** - точное копирование Node.js логики
2. **Убрать механизм удержания** - команда отправляется один раз
3. **Убрать все проверки** - режим, фаза, время

### Если Вариант 1 не работает:
1. **Попробовать Вариант 2** - с минимальной проверкой режима
2. **Проверить состояние контроллера** - режим, фаза, время
3. **Проверить логи контроллера** - найти ошибки или блокировки

---

## Важные замечания

1. **Режим ЖМ не должен отключаться автоматически** - нужна команда для перехода на другую программу управления
2. **Node.js код очень простой** - значит, проблема не в сложной логике
3. **Команда должна работать** - если Node.js код работает, значит контроллер может принимать команду
