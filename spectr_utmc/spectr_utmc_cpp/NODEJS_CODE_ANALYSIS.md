# Детальный анализ Node.js кода spectr_utmc.js

**Дата:** 2026-02-04  
**Цель:** Понять, как оригинальный Node.js код обрабатывает команду SET_YF

---

## 1. Реализация SET_YF в Node.js

### Код функции:
```javascript
SET_YF(e){
    return this.set(e,[
        {oid:l.utcType2OperationMode,type:u,value:3},
        {oid:l.utcControlFF,type:u,value:1}
    ])
}
```

Где:
- `l.utcType2OperationMode` = `"1.3.6.1.4.1.13267.3.2.4.1"` (режим работы)
- `l.utcControlFF` = `"1.3.6.1.4.1.13267.3.2.4.2.1.20"` (контроль мигания)
- `u` = `Integer` (тип данных SNMP)
- `e` = requestId (идентификатор запроса от ASUDD)

### Ключевые особенности:

1. **Однократная отправка** - команда отправляется один раз, без повторений
2. **Нет предварительных проверок** - не проверяет режим, фазу, время
3. **Две команды в одной транзакции** - обе SNMP SET команды отправляются одновременно
4. **Возвращает результат через callback** - `this.set()` вызывает `processResponse` при получении ответа

---

## 2. Метод set() - отправка SNMP команд

### Код:
```javascript
set(e,t){
    return this.session.set(t,((t,r)=>this.processResponse(t,r,e))),null
}
```

Где:
- `e` = requestId (идентификатор запроса)
- `t` = массив varbinds для SNMP SET
- `this.session` = SNMP сессия (net-snmp)
- Callback `processResponse` вызывается при получении ответа

### Особенности:
- Использует библиотеку `net-snmp` для отправки SNMP команд
- Отправляет команды на адрес контроллера из конфигурации (`addr`)
- Обрабатывает ответы через `processResponse`

---

## 3. Обработка ответов - processResponse()

### Логика обработки:
```javascript
processResponse(e,t,r){
    e?console.error(e.toString()):
    e=t.reduce(((e,t)=>{
        if(n.isVarbindError(t))
            return console.error(n.varbindError(t)),!0;
        const{oid:r,value:i}=t;
        return r===l.utcType2OperationMode&&this.changeState({controlSource:3===i?3:1}),
        e
    }),!1),
    void 0!==r&&this.protocol.send(a.formatResult(e?a.errInternal:a.errOK,r))
}
```

### Что происходит:
1. Проверяет наличие ошибок SNMP
2. Обрабатывает каждый varbind в ответе
3. Если получен `utcType2OperationMode`, обновляет состояние (`controlSource`)
4. Отправляет ответ ASUDD через протокол Spectr-ITS (`this.protocol.send()`)

---

## 4. Обработка SNMP уведомлений - processNotify()

### Логика:
```javascript
processNotify(e){
    const t=e.rinfo.address,
          r=h.objects[t];
    if(!r)return void console.log(`Tlc object ${t} not registred!`);
    console.log("Inform from",t);
    const i={};
    for(const{oid:t,type:r,value:n}of e.pdu.varbinds){
        const e=l.handlers[t];
        e?e.call(this,n,i,r):console.log("  ?",t,r,n)
    }
    if(Object.keys(i).length){
        const e={},
              {takt:t,stage:n,regime:s,controlSource:o}=i;
        void 0!==t?(e.stage=t,e.transition=n==t?0:255):
        void 0!==n&&n>48&&(e.stage=n-48,e.transition=0),
        void 0!==e.stage&&(e.stageLen=255,e.algorithm=1,e.regime=3),
        void 0!==s&&(e.regime=s),
        void 0!==o&&(e.controlSource=o),
        r.changeState(e),
        255===r.state.controlSource&&r.session.get([l.utcType2OperationMode],((e,t)=>r.processResponse(e,t)))
    }
}
```

### Что происходит:
1. Получает SNMP Inform/Trap от контроллера
2. Обрабатывает varbinds через `handlers`
3. Обновляет состояние контроллера (`changeState`)
4. Если `controlSource` неизвестен (255), делает GET запрос для проверки режима

### Обработчик utcReplyFR:
```javascript
[l.utcReplyFR]:(e,t)=>{e&&(t.regime=2)}
```

Когда контроллер отправляет `utcReplyFR=1`, это означает, что режим мигания активирован (`regime=2`).

---

## 5. Сравнение с другими командами

### SET_PHASE:
```javascript
SET_PHASE(e,t){
    const r=+t;
    return r>0&&r<8?
        this.set(e,[
            {oid:l.utcType2OperationMode,type:u,value:3},
            {oid:l.utcControlFn,type:c,value:Buffer.of(1<<r-1)}
        ]):
        a.errBadParam
}
```

**Отличия от SET_YF:**
- Проверяет параметр фазы (1-7)
- Использует `utcControlFn` вместо `utcControlFF`
- Использует `OctetString` (Buffer) вместо `Integer`

### SET_LOCAL:
```javascript
SET_LOCAL(e){
    return this.set(e,[
        {oid:l.utcControlLO,type:u,value:0},
        {oid:l.utcControlFF,type:u,value:0},
        {oid:l.utcType2OperationMode,type:u,value:1}
    ])
}
```

**Важно:** SET_LOCAL **отключает** мигание (`utcControlFF=0`) и переводит в локальный режим (`operationMode=1`).

---

## 6. Выводы и рекомендации

### Что мы узнали:

1. **Node.js код очень простой** - просто отправляет две SNMP команды один раз
2. **Нет сложной логики** - нет проверок режима, фазы, времени
3. **Нет удержания команды** - команда отправляется один раз
4. **Обработка ответов** - просто проверяет успешность и отправляет ответ ASUDD

### Почему это может работать в реальной системе:

1. **Контроллер уже в нужном состоянии:**
   - Контроллер постоянно находится в режиме UTC Control (3)
   - Контроллер имеет активную фазу
   - Минимальные периоды уже истекли

2. **ASUDD отправляет команду в правильный момент:**
   - ASUDD знает состояние контроллера
   - ASUDD отправляет команду только когда контроллер готов

3. **Контроллер работает в другом режиме:**
   - Возможно, контроллер работает в адаптивном режиме, а не фиксированном
   - Возможно, есть другие настройки, которые позволяют активацию мигания

### Что нужно проверить:

1. **Состояние контроллера в реальной системе:**
   - Какой режим работы (Standalone/UTC Control)?
   - Есть ли активная фаза?
   - Какие минимальные периоды установлены?

2. **Логи контроллера:**
   - Есть ли ошибки при получении команды SET_YF?
   - Есть ли блокировки или отказы?
   - Что происходит после получения команды?

3. **Конфигурация контроллера:**
   - Есть ли настройки, блокирующие активацию мигания?
   - Есть ли требования к режиму работы?
   - Есть ли требования к фазе?

---

## 7. Рекомендации для C++ реализации

### Вариант 1: Точное копирование Node.js логики

```cpp
bool setYF(int requestId) {
    // Просто отправляем две команды один раз
    std::vector<SnmpVarbind> varbinds = {
        {UTC_TYPE2_OPERATION_MODE, SnmpType::Integer, 3},
        {UTC_CONTROL_FF, SnmpType::Integer, 1}
    };
    return snmpSet(varbinds);
}
```

**Плюсы:** Точное соответствие оригинальному коду  
**Минусы:** Может не работать, если контроллер не готов

### Вариант 2: Улучшенная логика с проверками

```cpp
bool setYF(int requestId) {
    // 1. Проверить режим работы
    int currentMode = getOperationMode();
    if (currentMode != 3) {
        // Перевести в UTC Control
        if (!setOperationMode(3)) return false;
    }
    
    // 2. Проверить активную фазу
    int currentPhase = getCurrentPhase();
    if (currentPhase == 0 || currentPhase > 7) {
        // Установить фазу 1
        if (!setPhase(1)) return false;
    }
    
    // 3. Отправить команду SET_YF
    std::vector<SnmpVarbind> varbinds = {
        {UTC_TYPE2_OPERATION_MODE, SnmpType::Integer, 3},
        {UTC_CONTROL_FF, SnmpType::Integer, 1}
    };
    return snmpSet(varbinds);
}
```

**Плюсы:** Более надёжная работа  
**Минусы:** Может не соответствовать оригинальному поведению

### Вариант 3: Проверка готовности перед отправкой

```cpp
bool setYF(int requestId) {
    // Проверить, готов ли контроллер принять команду
    if (!isControllerReady()) {
        // Подождать или вернуть ошибку
        return false;
    }
    
    // Отправить команду
    std::vector<SnmpVarbind> varbinds = {
        {UTC_TYPE2_OPERATION_MODE, SnmpType::Integer, 3},
        {UTC_CONTROL_FF, SnmpType::Integer, 1}
    };
    return snmpSet(varbinds);
}
```

**Плюсы:** Проверяет готовность контроллера  
**Минусы:** Требует определения функции `isControllerReady()`

---

## 8. Следующие шаги

1. **Проверить логи контроллера** - найти ошибки или блокировки
2. **Проверить состояние контроллера** - режим, фаза, время
3. **Попробовать точное копирование Node.js логики** - без дополнительных проверок
4. **Проверить конфигурацию контроллера** - найти блокировки или требования
