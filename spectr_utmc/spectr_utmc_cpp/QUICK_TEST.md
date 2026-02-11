# Быстрый старт тестирования подключения к контроллеру

## Шаг 1: Сборка проекта

```bash
cd /home/alexey/shared_vm/spectr_utmc/spectr_utmc/spectr_utmc_cpp
mkdir -p build
cd build
cmake ..
make
```

После успешной сборки вы увидите два исполняемых файла:
- `spectr_utmc_cpp` - основное приложение
- `test_controller` - тестовая утилита

## Шаг 2: Тестирование подключения

### Вариант A: Использование интерактивного скрипта

```bash
cd ..
./test_connection.sh
```

Следуйте инструкциям на экране.

### Вариант B: Прямое подключение к контроллеру

Если у вас есть IP адрес контроллера и community string:

```bash
./build/test_controller connect <IP_ADDRESS> <COMMUNITY>
```

Пример:
```bash
./build/test_controller connect 192.168.4.77 UTMC
```

### Вариант C: Использование config.json

Если у вас есть файл конфигурации:

```bash
./build/test_controller test config.json
```

## Шаг 3: Интерпретация результатов

### ✅ Успешное подключение

Вы должны увидеть:
```
=== Testing Basic Connectivity ===
Address: 192.168.4.77
Community: UTMC

1. Creating SNMP session...
   OK: Session created successfully

2. Testing GET: sysUpTime...
   OK: Received 1 varbind(s)
  [0] OID: 1.3.6.1.2.1.1.3.0    Type: 67    Value: <время работы>

3. Testing GET: Application Version...
   OK: Received 1 varbind(s)
  [0] OID: 1.3.6.1.4.1.13267.3.2.1.2    Type: 4    Value: <версия>

4. Testing GET: Operation Mode...
   OK: Received 1 varbind(s)
  [0] OID: 1.3.6.1.4.1.13267.3.2.4.1    Type: 2    Value: <режим>
      Mode: Standalone/Monitor/UTC Control

5. Testing GET: Controller Time...
   OK: Received 1 varbind(s)
  [0] OID: 1.3.6.1.4.1.13267.3.2.3.2.0    Type: 4    Value: <время>
```

### ❌ Проблемы подключения

Если вы видите ошибки:

1. **"Failed to create SNMP session"**
   - Проверьте доступность контроллера: `ping <IP>`
   - Проверьте правильность IP адреса
   - Проверьте настройки firewall

2. **"GET failed"**
   - Проверьте community string (должен совпадать с настройками контроллера)
   - Попробуйте стандартные SNMP утилиты:
     ```bash
     snmpget -v 2c -c UTMC <IP> 1.3.6.1.2.1.1.3.0
     ```

3. **Пустые значения**
   - Контроллер может не поддерживать запрашиваемые OID
   - Проверьте версию прошивки контроллера

## Тестирование через VPN

Если вы работаете через VPN:

1. Убедитесь, что VPN активен и маршрутизирует трафик:
   ```bash
   ping <CONTROLLER_IP>
   ```

2. Проверьте доступность SNMP порта:
   ```bash
   nmap -sU -p 161 <CONTROLLER_IP>
   ```

3. Если ping работает, но SNMP нет - проверьте firewall правила

## Тестирование приема traps

Для проверки приема SNMP traps от контроллера:

```bash
./build/test_controller traps 10162 UTMC
```

Утилита будет ожидать входящие traps в течение 30 секунд.

**Важно:** Убедитесь, что контроллер настроен на отправку traps на ваш IP адрес и порт 10162.

## Следующие шаги

После успешного тестирования подключения:

1. Запустите основное приложение:
   ```bash
   ./build/spectr_utmc_cpp config.json
   ```

2. Проверьте логи приложения

3. Убедитесь, что контроллер отправляет traps на правильный адрес

## Полная документация

Подробная документация доступна в файле `TESTING.md`
