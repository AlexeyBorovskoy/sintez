#ifndef LOGGER_H
#define LOGGER_H

#include <string>
#include <mutex>
#include <sstream>
#include <chrono>
#include <iomanip>
#include <iostream>
#include <fstream>
#include <memory>

enum class LogLevel {
    TRACE = 0,
    DEBUG = 1,
    INFO = 2,
    WARNING = 3,
    ERROR = 4,
    FATAL = 5
};

class Logger {
public:
    static Logger& instance() {
        static Logger instance;
        return instance;
    }

    void setLevel(LogLevel level) { level_ = level; }
    LogLevel getLevel() const { return level_; }
    
    void setFile(const std::string& filename) {
        std::lock_guard<std::mutex> lock(mutex_);
        if (file_.is_open()) {
            file_.close();
        }
        file_.open(filename, std::ios::app);
        useFile_ = file_.is_open();
    }
    
    void setConsole(bool enabled) { useConsole_ = enabled; }

    template<typename... Args>
    void log(LogLevel level, const char* file, int line, const char* func, Args&&... args) {
        if (level < level_) return;
        
        std::ostringstream ss;
        ((ss << std::forward<Args>(args)), ...);
        
        write(level, file, line, func, ss.str());
    }

private:
    Logger() : level_(LogLevel::INFO), useConsole_(true), useFile_(false) {}
    ~Logger() {
        if (file_.is_open()) {
            file_.close();
        }
    }
    
    Logger(const Logger&) = delete;
    Logger& operator=(const Logger&) = delete;

    void write(LogLevel level, const char* file, int line, const char* func, const std::string& msg) {
        std::lock_guard<std::mutex> lock(mutex_);
        
        auto now = std::chrono::system_clock::now();
        auto time = std::chrono::system_clock::to_time_t(now);
        auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
            now.time_since_epoch()) % 1000;
        
        std::ostringstream ss;
        ss << std::put_time(std::localtime(&time), "%Y-%m-%d %H:%M:%S")
           << '.' << std::setfill('0') << std::setw(3) << ms.count()
           << " [" << levelToString(level) << "] "
           << extractFilename(file) << ":" << line << " " << func << "() - "
           << msg << "\n";
        
        std::string output = ss.str();
        
        if (useConsole_) {
            std::ostream& out = (level >= LogLevel::WARNING) ? std::cerr : std::cout;
            out << output;
            out.flush();
        }
        
        if (useFile_ && file_.is_open()) {
            file_ << output;
            file_.flush();
        }
    }
    
    static const char* levelToString(LogLevel level) {
        switch (level) {
            case LogLevel::TRACE:   return "TRACE";
            case LogLevel::DEBUG:   return "DEBUG";
            case LogLevel::INFO:    return "INFO ";
            case LogLevel::WARNING: return "WARN ";
            case LogLevel::ERROR:   return "ERROR";
            case LogLevel::FATAL:   return "FATAL";
            default:                return "?????";
        }
    }
    
    static std::string extractFilename(const char* path) {
        std::string p(path);
        size_t pos = p.find_last_of("/\\");
        return (pos != std::string::npos) ? p.substr(pos + 1) : p;
    }

    LogLevel level_;
    bool useConsole_;
    bool useFile_;
    std::ofstream file_;
    std::mutex mutex_;
};

#define LOG_TRACE(...) Logger::instance().log(LogLevel::TRACE, __FILE__, __LINE__, __func__, __VA_ARGS__)
#define LOG_DEBUG(...) Logger::instance().log(LogLevel::DEBUG, __FILE__, __LINE__, __func__, __VA_ARGS__)
#define LOG_INFO(...)  Logger::instance().log(LogLevel::INFO,  __FILE__, __LINE__, __func__, __VA_ARGS__)
#define LOG_WARN(...)  Logger::instance().log(LogLevel::WARNING, __FILE__, __LINE__, __func__, __VA_ARGS__)
#define LOG_ERROR(...) Logger::instance().log(LogLevel::ERROR, __FILE__, __LINE__, __func__, __VA_ARGS__)
#define LOG_FATAL(...) Logger::instance().log(LogLevel::FATAL, __FILE__, __LINE__, __func__, __VA_ARGS__)

#endif // LOGGER_H
