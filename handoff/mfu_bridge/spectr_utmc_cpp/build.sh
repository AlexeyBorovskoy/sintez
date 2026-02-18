#!/bin/bash
# Скрипт сборки проекта Spectr UTMC C++

set -e

echo "=== Сборка Spectr UTMC (C++) ==="
echo ""

# Проверка зависимостей
echo "Проверка зависимостей..."

if ! command -v g++ &> /dev/null; then
    echo "ОШИБКА: g++ не найден. Установка: sudo apt-get install build-essential"
    exit 1
fi

if ! command -v cmake &> /dev/null; then
    echo "ПРЕДУПРЕЖДЕНИЕ: cmake не найден. Пробую собрать без cmake..."
    USE_CMAKE=false
else
    USE_CMAKE=true
    echo "CMake найден: $(cmake --version | head -1)"
fi

if ! pkg-config --exists netsnmp; then
    echo "ОШИБКА: net-snmp не найден. Установка: sudo apt-get install libnetsnmp-dev"
    exit 1
fi

echo "net-snmp найден: $(pkg-config --modversion netsnmp)"
echo ""

# Создание директории сборки
mkdir -p build
cd build

if [ "$USE_CMAKE" = true ]; then
    echo "Сборка через CMake..."
    cmake ..
    make -j$(nproc)
else
    echo "Ручная сборка (без CMake)..."
    
    # Получение путей к библиотекам
    NETSNMP_CFLAGS=$(pkg-config --cflags netsnmp)
    NETSNMP_LIBS=$(pkg-config --libs netsnmp)
    
    # Компиляция
    echo "Компиляция исходников..."
    g++ -std=c++17 -Wall -O2 $NETSNMP_CFLAGS \
        -I../include \
        -c ../src/config.cpp -o config.o
    g++ -std=c++17 -Wall -O2 $NETSNMP_CFLAGS \
        -I../include \
        -c ../src/spectr_protocol.cpp -o spectr_protocol.o
    g++ -std=c++17 -Wall -O2 $NETSNMP_CFLAGS \
        -I../include \
        -c ../src/tcp_client.cpp -o tcp_client.o
    g++ -std=c++17 -Wall -O2 $NETSNMP_CFLAGS \
        -I../include \
        -c ../src/snmp_handler.cpp -o snmp_handler.o
    g++ -std=c++17 -Wall -O2 $NETSNMP_CFLAGS \
        -I../include \
        -c ../src/object_manager.cpp -o object_manager.o
    g++ -std=c++17 -Wall -O2 $NETSNMP_CFLAGS \
        -I../include \
        -c ../src/main.cpp -o main.o
    
    # Линковка
    echo "Линковка..."
    g++ -o spectr_utmc_cpp \
        config.o spectr_protocol.o tcp_client.o snmp_handler.o object_manager.o main.o \
        $NETSNMP_LIBS -lpthread
fi

if [ -f spectr_utmc_cpp ]; then
    echo ""
    echo "=== Сборка успешна ==="
    echo "Бинарник: $(pwd)/spectr_utmc_cpp"
    echo "Размер: $(du -h spectr_utmc_cpp | cut -f1)"
    echo ""
    echo "Для проверки:"
    echo "  cd build"
    echo "  ./spectr_utmc_cpp ../config.json"
else
    echo ""
    echo "=== Сборка не удалась ==="
    exit 1
fi
