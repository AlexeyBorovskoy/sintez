#include "config.h"
#include "snmp_handler.h"
#include "tcp_client.h"
#include "object_manager.h"
#include "spectr_protocol.h"
#include <iostream>
#include <map>
#include <memory>
#include <atomic>
#include <signal.h>
#include <unistd.h>

static std::atomic<bool> running(true);
static std::map<std::string, std::unique_ptr<SpectrObject>> objects;
static std::unique_ptr<SNMPHandler> snmpHandler;
static std::unique_ptr<TcpClient> tcpClient;

void signalHandler(int signal) {
    std::cout << "\nReceived signal " << signal << ", shutting down..." << std::endl;
    running = false;
}

static void sendToITSRaw(const std::string& data) {
    if (tcpClient && tcpClient->isConnected()) {
        tcpClient->send(data);
    }
}

void processITSData(const std::string& data) {
    // Парсинг потока данных от ITS сервера (с буферизацией фрагментов)
    static std::string buffer;
    buffer += data;

    size_t pos = 0;
    while ((pos = buffer.find('\r')) != std::string::npos) {
        std::string line = buffer.substr(0, pos);
        buffer.erase(0, pos + 1);

        // Trim like Node.js version
        auto first = line.find_first_not_of(" \t\n");
        if (first == std::string::npos) {
            continue;
        }
        auto last = line.find_last_not_of(" \t\n");
        line = line.substr(first, last - first + 1);

        // Парсинг команды
        auto parsed = SpectrProtocol::parseCommand(line);

        if (!parsed.isValid) {
            // Возврат ошибки как в Node.js версии
            std::string response = SpectrProtocol::formatResult(parsed.error, parsed.requestId);
            sendToITSRaw(response);
            continue;
        }
        
        // Попытка определить ID объекта из команды
        // В протоколе Spectr-ITS команды могут содержать ID объекта
        // Если не указан, используем первый объект
        // Поиск объекта по ID (если указан в команде)
        // В production нужна более сложная логика определения объекта
        SpectrObject* targetObject = nullptr;
        
        if (!objects.empty()) {
            // Пока используем первый объект, в production нужна маршрутизация
            targetObject = objects.begin()->second.get();
        }
        
        if (targetObject) {
            targetObject->processCommand(parsed);
        } else {
        std::cerr << "Не найден объект для команды: " << parsed.command << std::endl;
        }
    }
}

void processSNMPNotification(const SNMPNotification& notification) {
    // Поиск объекта по адресу источника
    auto it = objects.find(notification.sourceAddress);
    if (it != objects.end()) {
        it->second->processNotification(notification);
    } else {
        std::cout << "Объект Tlc " << notification.sourceAddress << " не зарегистрирован!" << std::endl;
    }
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Использование: " << argv[0] << " <config.json>" << std::endl;
        return 1;
    }
    
    // Установка обработчика сигналов
    signal(SIGINT, signalHandler);
    signal(SIGTERM, signalHandler);
    
    // Загрузка конфигурации
    Config config;
    if (!ConfigLoader::load(argv[1], config)) {
        std::cerr << "Не удалось загрузить конфигурацию" << std::endl;
        return 1;
    }
    
    std::cout << "Конфигурация загружена:" << std::endl;
    std::cout << "  ITS: " << config.its.host << ":" << config.its.port << std::endl;
    std::cout << "  SNMP community: " << config.community << std::endl;
    std::cout << "  ЖМ: confirmTimeoutSec=" << config.yf.confirmTimeoutSec
              << " keepPeriodMs=" << config.yf.keepPeriodMs
              << " maxHoldSec=" << config.yf.maxHoldSec << std::endl;
    std::cout << "  Объекты: " << config.objects.size() << std::endl;
    
    // Инициализация SNMP handler
    snmpHandler = std::make_unique<SNMPHandler>(config.community);
    
    // Инициализация TCP клиента для ITS сервера
    tcpClient = std::make_unique<TcpClient>(
        config.its.host, 
        config.its.port, 
        config.its.reconnectTimeout
    );
    
    tcpClient->setDataCallback(processITSData);
    tcpClient->setErrorCallback([](const std::string& error) {
        std::cerr << "TCP Client error: " << error << std::endl;
    });
    
    if (!tcpClient->start()) {
        std::cerr << "Failed to start TCP client" << std::endl;
        return 1;
    }
    
    // Создание объектов
    for (const auto& objConfig : config.objects) {
        std::string key = objConfig.addr.empty() ? objConfig.siteId : objConfig.addr;
        
        auto tcpClientPtr = tcpClient.get();
        auto obj = std::make_unique<SpectrObject>(objConfig, config.community, config.yf, snmpHandler.get(), tcpClientPtr);
        
        objects[key] = std::move(obj);
        
        std::cout << "Created object: " << objConfig.strid 
                  << " (ID: " << objConfig.id 
                  << ", Addr: " << objConfig.addr << ")" << std::endl;
    }
    
    // Запуск SNMP trap receiver
    if (!snmpHandler->startReceiver(10162, processSNMPNotification)) {
        std::cerr << "Failed to start SNMP receiver" << std::endl;
        return 1;
    }
    
    std::cout << "Spectr UTMC bridge started successfully" << std::endl;
    std::cout << "SNMP receiver listening on port 10162" << std::endl;
    std::cout << "Connecting to ITS server: " << config.its.host << ":" << config.its.port << std::endl;
    
    // Основной цикл
    while (running) {
        sleep(1);
        
        // Обновление состояний объектов
        for (auto& pair : objects) {
            pair.second->updateState();
        }
    }
    
    // Остановка сервисов
    std::cout << "Shutting down..." << std::endl;
    snmpHandler->stopReceiver();
    tcpClient->stop();
    
    objects.clear();
    snmpHandler.reset();
    tcpClient.reset();
    
    std::cout << "Shutdown complete" << std::endl;
    return 0;
}
