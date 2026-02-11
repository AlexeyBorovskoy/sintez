# Результаты тестирования чтения данных (GET операции)

**Дата:** 2026-02-03  
**Контроллер:** 192.168.75.150  
**Версия ПО контроллера:** 1.4.20  
**Community:** UTMC

---

## Итоговые результаты тестирования

### ✅ Все GET операции работают успешно:

1. **sysUpTime** (`1.3.6.1.2.1.1.3.0`)
   - ✅ Статус: Успешно
   - Значение: `Timeticks: (191813877) 22 days, 4:48:58.77`

2. **Application Version** (`1.3.6.1.4.1.13267.3.2.1.2`)
   - ✅ Статус: Успешно
   - Значение: `STRING: "1.4.20"`

3. **Operation Mode** (`1.3.6.1.4.1.13267.3.2.4.1`)
   - ✅ Статус: Успешно
   - Значение: `INTEGER: 1` (Standalone mode)
   - ⚠️ **Требует OID БЕЗ `.0`** (нестандартное поведение контроллера)

4. **Controller Time** (`1.3.6.1.4.1.13267.3.2.3.2`)
   - ✅ Статус: Успешно
   - Значение: `STRING: "20260203141322Z"` (формат YYYYMMDDHHmmssZ)
   - ⚠️ **Требует OID БЕЗ `.0`** (нестандартное поведение контроллера)

---

## Обнаруженная проблема и решение

### Проблема

Контроллер возвращал ошибку **"No Such Object available on this agent at this OID"** для:
- Operation Mode при использовании OID `1.3.6.1.4.1.13267.3.2.4.1.0` (с `.0`)
- Controller Time при использовании OID `1.3.6.1.4.1.13267.3.2.3.2.0` (с `.0`)

### Исследование

Проведено тестирование различных вариантов OID:

#### Operation Mode:
```bash
# Тест 1: OID БЕЗ .0
./build/test_controller get 192.168.75.150 UTMC 1.3.6.1.4.1.13267.3.2.4.1
# Результат: ✅ INTEGER: 1 (Standalone)

# Тест 2: OID С .0
./build/test_controller get 192.168.75.150 UTMC 1.3.6.1.4.1.13267.3.2.4.1.0
# Результат: ❌ No Such Object available on this agent at this OID
```

#### Controller Time:
```bash
# Тест 1: OID БЕЗ .0
./build/test_controller get 192.168.75.150 UTMC 1.3.6.1.4.1.13267.3.2.3.2
# Результат: ✅ STRING: "20260203141235Z"

# Тест 2: OID С .0
./build/test_controller get 192.168.75.150 UTMC 1.3.6.1.4.1.13267.3.2.3.2.0
# Результат: ❌ No Such Object available on this agent at this OID
```

### Выводы

1. **Контроллер НЕ требует `.0` для скалярных OID**, хотя:
   - Документация `protocol.txt` указывает `.0`
   - Стандарт SNMP требует `.0` для скалярных значений
   - MIB файл определяет эти объекты как скалярные

2. **Исходный Node.js код использует OID БЕЗ `.0`**:
   ```javascript
   session.get([l.utcType2OperationMode]  // БЕЗ .0
   ```

3. **Это особенность реализации контроллера** - возможно, связанная с версией прошивки или спецификой реализации SNMP агента.

---

## Исправления кода

### 1. `src/test_controller.cpp`

**Изменение 1:** Исправлен OID для Operation Mode
```cpp
// БЫЛО:
std::vector<std::string> oids3 = {SNMPOID::UTC_TYPE2_OPERATION_MODE + ".0"};

// СТАЛО:
// ВАЖНО: Этот контроллер требует OID БЕЗ .0 (в отличие от стандарта SNMP)
std::vector<std::string> oids3 = {SNMPOID::UTC_TYPE2_OPERATION_MODE};
```

**Изменение 2:** Исправлен OID для Controller Time
```cpp
// БЫЛО:
std::vector<std::string> oids4 = {"1.3.6.1.4.1.13267.3.2.3.2.0"};

// СТАЛО:
// ВАЖНО: Этот контроллер требует OID БЕЗ .0 (в отличие от стандарта SNMP)
std::vector<std::string> oids4 = {"1.3.6.1.4.1.13267.3.2.3.2"};
```

**Изменение 3:** Улучшен парсинг значения Operation Mode
```cpp
// Добавлен парсинг значения из формата "INTEGER: 1"
std::string valueStr = varbinds[i].value;
size_t colonPos = valueStr.find(':');
if (colonPos != std::string::npos) {
    valueStr = valueStr.substr(colonPos + 1);
}
valueStr.erase(0, valueStr.find_first_not_of(" \t"));
valueStr.erase(valueStr.find_last_not_of(" \t") + 1);
int mode = std::stoi(valueStr);
```

**Изменение 4:** Добавлена команда `get` для тестирования отдельных OID
```cpp
void testGetOID(SNMPHandler& handler, const std::string& address, const std::string& oid) {
    std::cout << "\n=== Testing GET: " << oid << " ===" << std::endl;
    std::vector<std::string> oids = {oid};
    bool success = handler.get(address, oids, [](bool error, const std::vector<SNMPVarbind>& varbinds) {
        // ... обработка результатов
    });
}
```

### 2. `src/object_manager.cpp`

**Изменение:** Исправлен OID для Operation Mode в `requestOperationMode()`
```cpp
// БЫЛО:
// Для GET запросов скалярных значений в SNMP требуется .0 в конце OID
std::vector<std::string> oids = {SNMPOID::UTC_TYPE2_OPERATION_MODE + ".0"};

// СТАЛО:
// ВАЖНО: Этот контроллер требует OID БЕЗ .0 (в отличие от стандарта SNMP)
// Node.js библиотека автоматически добавляет .0, но контроллер работает без него
std::vector<std::string> oids = {SNMPOID::UTC_TYPE2_OPERATION_MODE};
```

---

## Полный вывод тестирования

```
=== Testing Basic Connectivity ===
Address: 192.168.75.150
Community: UTMC

1. Creating SNMP session...
   OK: Session created successfully

2. Testing GET: sysUpTime (1.3.6.1.2.1.1.3.0)...
   OK: Received 1 varbind(s)
  [0] OID: iso.3.6.1.2.1.1.3.0                                Type: 67              Value: Timeticks: (191813877) 22 days, 4:48:58.77

3. Testing GET: Application Version (1.3.6.1.4.1.13267.3.2.1.2)...
   OK: Received 1 varbind(s)
  [0] OID: iso.3.6.1.4.1.13267.3.2.1.2                        Type: 4               Value: STRING: "1.4.20"

4. Testing GET: Operation Mode (1.3.6.1.4.1.13267.3.2.4.1)...
   OK: Received 1 varbind(s)
  [0] OID: iso.3.6.1.4.1.13267.3.2.4.1                        Type: 2               Value: INTEGER: 1
      Mode: Standalone

5. Testing GET: Controller Time (1.3.6.1.4.1.13267.3.2.3.2)...
   OK: Received 1 varbind(s)
  [0] OID: iso.3.6.1.4.1.13267.3.2.3.2                        Type: 4               Value: STRING: "20260203141322Z"

=== Basic Connectivity Test Complete ===
```

---

## Рекомендации

1. **Для GET запросов** использовать OID БЕЗ `.0` для этого контроллера
2. **Для SET запросов** проверить, требуется ли `.0` (обычно для SET не требуется)
3. **Документировать** эту особенность контроллера для будущих разработчиков
4. **При работе с другими контроллерами** проверить их поведение относительно `.0`

---

## Сравнение с исходным проектом

### Node.js версия:
```javascript
// Использует OID БЕЗ .0
session.get([l.utcType2OperationMode]  // = "1.3.6.1.4.1.13267.3.2.4.1"
```

### C++ версия (после исправления):
```cpp
// Использует OID БЕЗ .0 (соответствует Node.js версии)
std::vector<std::string> oids = {SNMPOID::UTC_TYPE2_OPERATION_MODE};  // БЕЗ .0
```

✅ **Соответствие достигнуто**

---

## Статус

✅ **Все тесты чтения данных (GET операции) проходят успешно**

Следующие шаги:
- Тестирование SET операций
- Тестирование приема SNMP traps
- Интеграционное тестирование с Spectr-ITS протоколом
