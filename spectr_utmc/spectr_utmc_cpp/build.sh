#!/bin/bash
# Скрипт сборки проекта Spectr UTMC C++

set -e

echo "=== Spectr UTMC C++ Build Script ==="
echo ""

# Проверка зависимостей
echo "Checking dependencies..."

if ! command -v g++ &> /dev/null; then
    echo "ERROR: g++ not found. Install with: sudo apt-get install build-essential"
    exit 1
fi

if ! command -v cmake &> /dev/null; then
    echo "WARNING: cmake not found. Trying to build without cmake..."
    USE_CMAKE=false
else
    USE_CMAKE=true
    echo "CMake found: $(cmake --version | head -1)"
fi

if ! pkg-config --exists netsnmp; then
    echo "ERROR: net-snmp not found. Install with: sudo apt-get install libnetsnmp-dev"
    exit 1
fi

echo "net-snmp found: $(pkg-config --modversion netsnmp)"
echo ""

# Создание директории сборки
mkdir -p build
cd build

if [ "$USE_CMAKE" = true ]; then
    echo "Building with CMake..."
    cmake ..
    make -j$(nproc)
else
    echo "Building manually (without CMake)..."
    
    # Получение путей к библиотекам
    NETSNMP_CFLAGS=$(pkg-config --cflags netsnmp)
    NETSNMP_LIBS=$(pkg-config --libs netsnmp)
    
    # Компиляция
    echo "Compiling sources..."
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
    echo "Linking..."
    g++ -o spectr_utmc_cpp \
        config.o spectr_protocol.o tcp_client.o snmp_handler.o object_manager.o main.o \
        $NETSNMP_LIBS -lpthread
fi

if [ -f spectr_utmc_cpp ]; then
    echo ""
    echo "=== Build successful! ==="
    echo "Executable: $(pwd)/spectr_utmc_cpp"
    echo "Size: $(du -h spectr_utmc_cpp | cut -f1)"
    echo ""
    echo "To test:"
    echo "  cd build"
    echo "  ./spectr_utmc_cpp ../config.json"
else
    echo ""
    echo "=== Build failed! ==="
    exit 1
fi
