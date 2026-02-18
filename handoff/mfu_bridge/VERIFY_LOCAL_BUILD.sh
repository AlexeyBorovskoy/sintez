#!/bin/sh
set -eu

# Проверка локальной сборки на ПК (Linux x86_64, НЕ OpenWrt).
# Требуется: cmake, C++ компилятор, dev-пакеты net-snmp.

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

cd "$DIR/spectr_utmc_cpp"

cmake -S . -B build
cmake --build build -j

# Ожидаемые бинарники:
# - build/spectr_utmc_cpp
# - build/test_controller
ls -la build/spectr_utmc_cpp build/test_controller
