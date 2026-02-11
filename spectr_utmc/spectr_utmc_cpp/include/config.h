#ifndef CONFIG_H
#define CONFIG_H

#include <string>
#include <vector>
#include <cstdint>

struct ITSConfig {
    std::string host;
    uint16_t port;
    int reconnectTimeout;
};

struct ObjectConfig {
    uint32_t id;
    std::string strid;
    std::string addr;
    std::string siteId;
};

struct Config {
    ITSConfig its;
    std::string community;
    std::vector<ObjectConfig> objects;
};

class ConfigLoader {
public:
    static bool load(const std::string& filename, Config& config);
    static bool save(const std::string& filename, const Config& config);
};

#endif // CONFIG_H
