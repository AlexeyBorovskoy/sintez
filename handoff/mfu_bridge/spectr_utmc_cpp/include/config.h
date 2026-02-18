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

struct YFConfig {
    // Сколько пытаться подтвердить ЖМ по utcReplyFR перед тем как сдаться.
    int confirmTimeoutSec;
    // How often to reassert utcControlFF=1 while YF is enabled.
    int keepPeriodMs;
    // 0 = infinite (until another command disables/overrides YF).
    int maxHoldSec;
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
    YFConfig yf;
    std::vector<ObjectConfig> objects;
};

class ConfigLoader {
public:
    static bool load(const std::string& filename, Config& config);
    static bool save(const std::string& filename, const Config& config);
};

#endif // CONFIG_H
