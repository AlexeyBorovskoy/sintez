#include "config.h"
#include "logger.h"
#include <fstream>
#include <sstream>
#include <cstdlib>
#include <regex>
#include <algorithm>

bool ConfigLoader::load(const std::string& filename, Config& config) {
    std::ifstream file(filename);
    if (!file.is_open()) {
        LOG_ERROR("Cannot open config file: ", filename);
        return false;
    }
    
    std::stringstream buffer;
    buffer << file.rdbuf();
    std::string json = buffer.str();
    
    return parseJson(json, config);
}

bool ConfigLoader::loadWithEnv(const std::string& filename, Config& config) {
    // Сначала загружаем из файла
    if (!load(filename, config)) {
        return false;
    }
    
    // Переопределяем из переменных окружения
    if (auto val = getEnv("SPECTR_ITS_HOST")) {
        config.its.host = *val;
        LOG_INFO("ITS host overridden from env: ", *val);
    }
    if (auto val = getEnv("SPECTR_ITS_PORT")) {
        config.its.port = static_cast<uint16_t>(std::stoi(*val));
        LOG_INFO("ITS port overridden from env: ", *val);
    }
    if (auto val = getEnv("SPECTR_ITS_RECONNECT_TIMEOUT")) {
        config.its.reconnectTimeout = std::stoi(*val);
    }
    
    if (auto val = getEnv("SPECTR_SNMP_COMMUNITY")) {
        config.snmp.community = *val;
        LOG_INFO("SNMP community overridden from env");
    }
    if (auto val = getEnv("SPECTR_SNMP_TRAP_PORT")) {
        config.snmp.trapPort = static_cast<uint16_t>(std::stoi(*val));
        LOG_INFO("SNMP trap port overridden from env: ", *val);
    }
    
    if (auto val = getEnv("SPECTR_LOG_LEVEL")) {
        config.log.level = *val;
    }
    if (auto val = getEnv("SPECTR_LOG_FILE")) {
        config.log.file = *val;
    }
    
    return true;
}

bool ConfigLoader::validate(const Config& config, std::string& error) {
    if (config.its.host.empty()) {
        error = "ITS host is empty";
        return false;
    }
    if (config.its.port == 0) {
        error = "ITS port is invalid";
        return false;
    }
    if (config.snmp.community.empty()) {
        error = "SNMP community is empty";
        return false;
    }
    if (config.objects.empty()) {
        error = "No objects configured";
        return false;
    }
    
    for (const auto& obj : config.objects) {
        if (obj.id == 0) {
            error = "Object ID is zero";
            return false;
        }
        if (obj.addr.empty() && obj.siteId.empty()) {
            error = "Object has no address or siteId";
            return false;
        }
    }
    
    return true;
}

std::optional<std::string> ConfigLoader::getEnv(const std::string& name) {
    const char* val = std::getenv(name.c_str());
    if (val) {
        return std::string(val);
    }
    return std::nullopt;
}

bool ConfigLoader::parseJson(const std::string& json, Config& config) {
    try {
        // Парсинг ITS секции
        size_t itsPos = json.find("\"its\"");
        if (itsPos != std::string::npos) {
            size_t braceStart = json.find('{', itsPos);
            size_t braceEnd = json.find('}', braceStart);
            if (braceStart != std::string::npos && braceEnd != std::string::npos) {
                std::string itsJson = json.substr(braceStart, braceEnd - braceStart + 1);
                config.its.host = extractString(itsJson, "host");
                config.its.port = static_cast<uint16_t>(extractInt(itsJson, "port", 3000));
                config.its.reconnectTimeout = extractInt(itsJson, "reconnectTimeout", 10);
            }
        }
        
        // Парсинг SNMP секции (если есть) или community из корня
        size_t snmpPos = json.find("\"snmp\"");
        if (snmpPos != std::string::npos) {
            size_t braceStart = json.find('{', snmpPos);
            size_t braceEnd = json.find('}', braceStart);
            if (braceStart != std::string::npos && braceEnd != std::string::npos) {
                std::string snmpJson = json.substr(braceStart, braceEnd - braceStart + 1);
                config.snmp.community = extractString(snmpJson, "community");
                config.snmp.trapPort = static_cast<uint16_t>(extractInt(snmpJson, "trapPort", 10162));
                config.snmp.timeout = extractInt(snmpJson, "timeout", 5);
                config.snmp.retries = extractInt(snmpJson, "retries", 3);
            }
        } else {
            // Совместимость со старым форматом
            std::string community = extractString(json, "community");
            if (!community.empty()) {
                config.snmp.community = community;
            }
        }
        
        // Парсинг Log секции
        size_t logPos = json.find("\"log\"");
        if (logPos != std::string::npos) {
            size_t braceStart = json.find('{', logPos);
            size_t braceEnd = json.find('}', braceStart);
            if (braceStart != std::string::npos && braceEnd != std::string::npos) {
                std::string logJson = json.substr(braceStart, braceEnd - braceStart + 1);
                config.log.level = extractString(logJson, "level");
                config.log.file = extractString(logJson, "file");
                config.log.console = extractBool(logJson, "console", true);
            }
        }
        
        // Парсинг objects
        size_t objPos = json.find("\"objects\"");
        if (objPos != std::string::npos) {
            size_t arrayStart = json.find('[', objPos);
            size_t arrayEnd = json.find(']', arrayStart);
            
            if (arrayStart != std::string::npos && arrayEnd != std::string::npos) {
                std::string arrayJson = json.substr(arrayStart + 1, arrayEnd - arrayStart - 1);
                
                // Найти все объекты в массиве
                size_t pos = 0;
                while (pos < arrayJson.length()) {
                    size_t objStart = arrayJson.find('{', pos);
                    if (objStart == std::string::npos) break;
                    
                    size_t objEnd = arrayJson.find('}', objStart);
                    if (objEnd == std::string::npos) break;
                    
                    std::string objJson = arrayJson.substr(objStart, objEnd - objStart + 1);
                    
                    ObjectConfig obj;
                    obj.id = static_cast<uint32_t>(extractInt(objJson, "id"));
                    obj.strid = extractString(objJson, "strid");
                    obj.addr = extractString(objJson, "addr");
                    obj.siteId = extractString(objJson, "siteId");
                    
                    // Также проверяем //siteId (комментарий)
                    if (obj.siteId.empty()) {
                        obj.siteId = extractString(objJson, "//siteId");
                    }
                    
                    if (obj.id > 0) {
                        config.objects.push_back(obj);
                    }
                    
                    pos = objEnd + 1;
                }
            }
        }
        
        return true;
    } catch (const std::exception& e) {
        LOG_ERROR("JSON parse error: ", e.what());
        return false;
    }
}

std::string ConfigLoader::extractString(const std::string& json, const std::string& key) {
    std::string searchKey = "\"" + key + "\"";
    size_t keyPos = json.find(searchKey);
    if (keyPos == std::string::npos) return "";
    
    size_t colonPos = json.find(':', keyPos);
    if (colonPos == std::string::npos) return "";
    
    size_t valueStart = json.find('"', colonPos);
    if (valueStart == std::string::npos) return "";
    
    size_t valueEnd = json.find('"', valueStart + 1);
    if (valueEnd == std::string::npos) return "";
    
    return json.substr(valueStart + 1, valueEnd - valueStart - 1);
}

int ConfigLoader::extractInt(const std::string& json, const std::string& key, int defaultValue) {
    std::string searchKey = "\"" + key + "\"";
    size_t keyPos = json.find(searchKey);
    if (keyPos == std::string::npos) return defaultValue;
    
    size_t colonPos = json.find(':', keyPos);
    if (colonPos == std::string::npos) return defaultValue;
    
    // Пропускаем пробелы
    size_t valueStart = colonPos + 1;
    while (valueStart < json.length() && (json[valueStart] == ' ' || json[valueStart] == '\t')) {
        valueStart++;
    }
    
    if (valueStart >= json.length()) return defaultValue;
    
    // Ищем число
    size_t valueEnd = valueStart;
    while (valueEnd < json.length() && (std::isdigit(json[valueEnd]) || json[valueEnd] == '-')) {
        valueEnd++;
    }
    
    if (valueEnd == valueStart) return defaultValue;
    
    try {
        return std::stoi(json.substr(valueStart, valueEnd - valueStart));
    } catch (...) {
        return defaultValue;
    }
}

bool ConfigLoader::extractBool(const std::string& json, const std::string& key, bool defaultValue) {
    std::string searchKey = "\"" + key + "\"";
    size_t keyPos = json.find(searchKey);
    if (keyPos == std::string::npos) return defaultValue;
    
    size_t colonPos = json.find(':', keyPos);
    if (colonPos == std::string::npos) return defaultValue;
    
    size_t truePos = json.find("true", colonPos);
    size_t falsePos = json.find("false", colonPos);
    
    if (truePos != std::string::npos && (falsePos == std::string::npos || truePos < falsePos)) {
        return true;
    }
    if (falsePos != std::string::npos) {
        return false;
    }
    
    return defaultValue;
}
