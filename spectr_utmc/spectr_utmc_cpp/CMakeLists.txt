cmake_minimum_required(VERSION 3.10)
project(spectr_utmc_cpp)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Поиск зависимостей
find_package(PkgConfig REQUIRED)
pkg_check_modules(NETSNMP REQUIRED netsnmp)

# Включаемые директории
include_directories(${CMAKE_SOURCE_DIR}/include)
include_directories(${NETSNMP_INCLUDE_DIRS})

# Исходные файлы
set(SOURCES
    src/main.cpp
    src/config.cpp
    src/snmp_handler.cpp
    src/tcp_client.cpp
    src/spectr_protocol.cpp
    src/object_manager.cpp
)

# Заголовочные файлы
set(HEADERS
    include/config.h
    include/snmp_handler.h
    include/tcp_client.h
    include/spectr_protocol.h
    include/object_manager.h
)

# Исполняемый файл
add_executable(spectr_utmc_cpp ${SOURCES} ${HEADERS})

# Линковка библиотек
target_link_libraries(spectr_utmc_cpp 
    ${NETSNMP_LIBRARIES}
    pthread
)

# Флаги компиляции
target_compile_options(spectr_utmc_cpp PRIVATE ${NETSNMP_CFLAGS_OTHER})

# Тестовая утилита для проверки подключения к контроллеру
set(TEST_SOURCES
    src/test_controller.cpp
    src/config.cpp
    src/snmp_handler.cpp
)

add_executable(test_controller ${TEST_SOURCES} ${HEADERS})

target_link_libraries(test_controller 
    ${NETSNMP_LIBRARIES}
    pthread
)

target_compile_options(test_controller PRIVATE ${NETSNMP_CFLAGS_OTHER})

# Установка
install(TARGETS spectr_utmc_cpp test_controller DESTINATION bin)
