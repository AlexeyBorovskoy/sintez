#ifndef CONFIG_H
#define CONFIG_H

#include <string>
#include <vector>
#include <optional>
#include <cstdint>

struct ITSConfig {
    std::string host = "localhost";
    uint16_t port = 3000;
    int reconnectTimeout = 10;  // секунды
};

struct ObjectConfig {
    uint32_t id = 0;
    std::string strid;
    std::string addr;
    std::string siteId;
};

struct SNMPConfig {
    std::string community = "UTMC";
    uint16_t trapPort = 10162;
    int timeout = 5;     // секунды
    int retries = 3;
};

struct LogConfig {
    std::string level = "INFO";
    std::string file;
    bool console = true;
};

struct Config {
    ITSConfig its;
    SNMPConfig snmp;
    LogConfig log;
    std::vector<ObjectConfig> objects;
};

class ConfigLoader {
public:
    // Загрузка конфигурации из файла
    static bool load(const std::string& filename, Config& config);
    
    // Загрузка конфигурации с учётом переменных окружения (для Docker)
    static bool loadWithEnv(const std::string& filename, Config& config);
    
    // Валидация конфигурации
    static bool validate(const Config& config, std::string& error);
    
private:
    // Получение значения из переменной окружения
    static std::optional<std::string> getEnv(const std::string& name);
    
    // Парсинг JSON
    static bool parseJson(const std::string& json, Config& config);
    
    // Вспомогательные функции для парсинга
    static std::string extractString(const std::string& json, const std::string& key);
    static int extractInt(const std::string& json, const std::string& key, int defaultValue = 0);
    static bool extractBool(const std::string& json, const std::string& key, bool defaultValue = false);
};

#endif // CONFIG_H
