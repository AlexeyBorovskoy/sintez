# Инструкция по сборке

## Требования

- C++17 компилятор (g++ 7+ или clang++ 5+)
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

После успешной сборки исполняемый файл будет находиться в `build/spectr_utmc_cpp`

## Установка

```bash
sudo cp build/spectr_utmc_cpp /usr/local/bin/
sudo chmod +x /usr/local/bin/spectr_utmc_cpp
```

## Отладка сборки

Если возникают проблемы с поиском net-snmp:

```bash
# Проверка установки net-snmp
pkg-config --modversion netsnmp

# Указание пути к библиотекам вручную
cmake .. -DNETSNMP_INCLUDE_DIR=/usr/include/net-snmp -DNETSNMP_LIB_DIR=/usr/lib/x86_64-linux-gnu
```

## Проверка зависимостей

```bash
# Проверка наличия библиотек
ldconfig -p | grep netsnmp

# Проверка заголовочных файлов
ls /usr/include/net-snmp/
```
