# Инструкция по сборке для тестирования на сервере

## Требования

Для сборки проекта на сервере нужны следующие зависимости:

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y build-essential cmake pkg-config libsnmp-dev

# CentOS/RHEL
sudo yum install -y gcc-c++ cmake pkgconfig net-snmp-devel
```

## Сборка проекта

```bash
cd /home/alexey/shared_vm/spectr_utmc/spectr_utmc/spectr_utmc_cpp
mkdir -p build
cd build
cmake ..
make
```

После успешной сборки будут созданы:
- `build/spectr_utmc_cpp` - основное приложение
- `build/test_controller` - тестовая утилита для чтения данных

## Проверка сборки

```bash
# Проверить наличие бинарников
ls -lh build/test_controller build/spectr_utmc_cpp

# Проверить зависимости
ldd build/test_controller
```

## Быстрый тест после сборки

```bash
# Проверить, что утилита запускается
./build/test_controller --help 2>&1 || ./build/test_controller 2>&1 | head -5
```

---

## После сборки можно переходить к тестированию

См. `TEST_READ_PLAN.md` для пошагового плана тестирования.
