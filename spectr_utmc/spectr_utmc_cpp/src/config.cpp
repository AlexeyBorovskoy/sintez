#include "config.h"
#include <fstream>
#include <iostream>
#include <sstream>

// Простой JSON парсер для нашей конфигурации
// В production лучше использовать библиотеку типа nlohmann/json

namespace {
    std::string trim(const std::string& str) {
        size_t first = str.find_first_not_of(" \t\n\r");
        if (first == std::string::npos) return "";
        size_t last = str.find_last_not_of(" \t\n\r");
        return str.substr(first, (last - first + 1));
    }

    std::string extractString(const std::string& json, const std::string& key) {
        std::string search = "\"" + key + "\"";
        size_t pos = json.find(search);
        if (pos == std::string::npos) return "";
        
        pos = json.find(":", pos);
        if (pos == std::string::npos) return "";
        pos++;
        
        size_t start = json.find("\"", pos);
        if (start == std::string::npos) return "";
        start++;
        
        size_t end = json.find("\"", start);
        if (end == std::string::npos) return "";
        
        return json.substr(start, end - start);
    }

    int extractInt(const std::string& json, const std::string& key) {
        std::string search = "\"" + key + "\"";
        size_t pos = json.find(search);
        if (pos == std::string::npos) return 0;
        
        pos = json.find(":", pos);
        if (pos == std::string::npos) return 0;
        pos++;
        
        while (pos < json.length() && (json[pos] == ' ' || json[pos] == '\t')) pos++;
        
        size_t end = pos;
        while (end < json.length() && 
               json[end] != ',' && json[end] != '}' && json[end] != '\n' && json[end] != ' ') {
            end++;
        }
        
        std::string value = json.substr(pos, end - pos);
        return std::stoi(value);
    }
}

bool ConfigLoader::load(const std::string& filename, Config& config) {
    std::ifstream file(filename);
    if (!file.is_open()) {
        std::cerr << "Failed to open config file: " << filename << std::endl;
        return false;
    }

    // Reset output to avoid leaking values across reloads.
    config = Config{};
    config.objects.clear();

    std::stringstream buffer;
    buffer << file.rdbuf();
    std::string json = buffer.str();
    file.close();

    // Парсинг ITS конфигурации
    size_t itsStart = json.find("\"its\"");
    if (itsStart != std::string::npos) {
        size_t itsEnd = json.find("}", itsStart);
        if (itsEnd != std::string::npos) {
            std::string itsSection = json.substr(itsStart, itsEnd - itsStart);
            config.its.host = extractString(itsSection, "host");
            config.its.port = extractInt(itsSection, "port");
            config.its.reconnectTimeout = extractInt(itsSection, "reconnectTimeout");
        }
    }

    // Парсинг community
    config.community = extractString(json, "community");

    // Парсинг yf конфигурации
    config.yf.confirmTimeoutSec = 120;
    config.yf.keepPeriodMs = 2000;
    config.yf.maxHoldSec = 0;
    size_t yfStart = json.find("\"yf\"");
    if (yfStart != std::string::npos) {
        size_t yfEnd = json.find("}", yfStart);
        if (yfEnd != std::string::npos) {
            std::string yfSection = json.substr(yfStart, yfEnd - yfStart);
            int confirmTimeoutSec = extractInt(yfSection, "confirmTimeoutSec");
            int keepPeriodMs = extractInt(yfSection, "keepPeriodMs");
            int maxHoldSec = extractInt(yfSection, "maxHoldSec");
            if (confirmTimeoutSec > 0) config.yf.confirmTimeoutSec = confirmTimeoutSec;
            if (keepPeriodMs > 0) config.yf.keepPeriodMs = keepPeriodMs;
            if (maxHoldSec >= 0) config.yf.maxHoldSec = maxHoldSec;
        }
    }

    // Парсинг objects
    size_t objectsStart = json.find("\"objects\"");
    if (objectsStart != std::string::npos) {
        objectsStart = json.find("[", objectsStart);
        if (objectsStart != std::string::npos) {
            size_t objectsEnd = json.find("]", objectsStart);
            if (objectsEnd != std::string::npos) {
                std::string objectsSection = json.substr(objectsStart, objectsEnd - objectsStart);
                
                size_t objStart = 0;
                while ((objStart = objectsSection.find("{", objStart)) != std::string::npos) {
                    size_t objEnd = objectsSection.find("}", objStart);
                    if (objEnd == std::string::npos) break;
                    
                    std::string objJson = objectsSection.substr(objStart, objEnd - objStart);
                    
                    ObjectConfig obj;
                    obj.id = extractInt(objJson, "id");
                    obj.strid = extractString(objJson, "strid");
                    obj.addr = extractString(objJson, "addr");
                    obj.siteId = extractString(objJson, "siteId");
                    
                    if (!obj.addr.empty() || !obj.siteId.empty()) {
                        config.objects.push_back(obj);
                    }
                    
                    objStart = objEnd + 1;
                }
            }
        }
    }

    // Значения по умолчанию (как в Node.js версии)
    if (config.its.host.empty()) {
        config.its.host = "localhost";
    }
    if (config.its.port == 0) {
        config.its.port = 3000;
    }
    if (config.its.reconnectTimeout == 0) {
        config.its.reconnectTimeout = 10;
    }
    if (config.community.empty()) {
        config.community = "UTMC";
    }

    // Валидация
    if (config.objects.empty()) {
        std::cerr << "No objects configured" << std::endl;
        return false;
    }

    return true;
}

bool ConfigLoader::save(const std::string& filename, const Config& config) {
    // Реализация сохранения (если потребуется)
    return false;
}
