#include "spectr_protocol.h"
#include "logger.h"
#include <sstream>
#include <iomanip>
#include <ctime>
#include <algorithm>
#include <cctype>
#include <chrono>

uint8_t SpectrProtocol::checksum(const std::string& data) {
    // Алгоритм контрольной суммы из оригинального Node.js кода
    // Это специфичный для Spectr-ITS алгоритм
    uint16_t sum = 0;
    for (char c : data) {
        sum += static_cast<uint8_t>(c);
        
        // Если есть перенос в 9-й бит, добавляем 1
        if (sum & 0x100) {
            sum++;
        }
        
        // Если установлен бит 7 (0x80), удваиваем и добавляем 1
        if (sum & 0x80) {
            sum = (sum << 1) + 1;
        } else {
            sum <<= 1;
        }
        
        // Оставляем только младший байт
        sum &= 0xFF;
    }
    
    return static_cast<uint8_t>(sum);
}

bool SpectrProtocol::verifyChecksum(const std::string& data) {
    size_t dollarPos = data.find_last_of('$');
    if (dollarPos == std::string::npos || data.length() < dollarPos + 3) {
        return false;
    }
    
    std::string dataWithoutChecksum = data.substr(0, dollarPos);
    std::string checksumStr = data.substr(dollarPos + 1, 2);
    
    try {
        uint8_t receivedChecksum = static_cast<uint8_t>(std::stoi(checksumStr, nullptr, 16));
        uint8_t calculatedChecksum = checksum(dataWithoutChecksum);
        return receivedChecksum == calculatedChecksum;
    } catch (...) {
        return false;
    }
}

std::string SpectrProtocol::appendChecksum(const std::string& data) {
    uint8_t chk = checksum(data);
    std::ostringstream ss;
    ss << data << "$" << std::hex << std::setw(2) << std::setfill('0') 
       << static_cast<int>(chk) << "\r";
    return ss.str();
}

const char* SpectrProtocol::errorToString(SpectrError error) {
    switch (error) {
        case SpectrError::OK:          return ">O.K.";
        case SpectrError::OFF_LINE:    return ">OFF_LINE";
        case SpectrError::BAD_CHECK:   return ">BAD_CHECK";
        case SpectrError::UNINDENT:    return ">UNINDENT";
        case SpectrError::BROKEN:      return ">BROKEN";
        case SpectrError::TOO_LONG:    return ">TOO_LONG";
        case SpectrError::BAD_DATA:    return ">BAD_DATA";
        case SpectrError::BAD_PARAM:   return ">BAD_PARAM";
        case SpectrError::NOT_EXEC_1:
        case SpectrError::NOT_EXEC_2:
        case SpectrError::NOT_EXEC_3:
        case SpectrError::NOT_EXEC_4:
        case SpectrError::NOT_EXEC_5:
        case SpectrError::NOT_EXEC_255: return ">NOT_EXEC";
        default:                        return ">ERROR";
    }
}

std::string SpectrProtocol::formatResult(SpectrError error, const std::string& requestId) {
    std::ostringstream ss;
    ss << "!" << getTime() << " " << errorToString(error);
    if (!requestId.empty()) {
        ss << " " << requestId;
    }
    ss << "\r";
    return ss.str();
}

std::string SpectrProtocol::formatResult(SpectrError error, const std::string& requestId, const std::string& data) {
    if (error == SpectrError::OK) {
        std::ostringstream ss;
        ss << "#" << getTime() << " >O.K. " << requestId << " " << data;
        return appendChecksum(ss.str());
    } else {
        return formatResult(error, requestId);
    }
}

std::string SpectrProtocol::getTime() {
    auto now = std::chrono::system_clock::now();
    auto time = std::chrono::system_clock::to_time_t(now);
    std::tm* local = std::localtime(&time);
    
    std::ostringstream ss;
    ss << std::setfill('0') 
       << std::setw(2) << local->tm_hour << ":"
       << std::setw(2) << local->tm_min << ":"
       << std::setw(2) << local->tm_sec;
    return ss.str();
}

std::string SpectrProtocol::toHex(const std::string& data) {
    std::ostringstream ss;
    for (unsigned char c : data) {
        ss << std::hex << std::setw(2) << std::setfill('0') << static_cast<int>(c);
    }
    return ss.str();
}

std::string SpectrProtocol::fromHex(const std::string& hex) {
    std::string result;
    for (size_t i = 0; i + 1 < hex.length(); i += 2) {
        try {
            unsigned char c = static_cast<unsigned char>(std::stoi(hex.substr(i, 2), nullptr, 16));
            result += c;
        } catch (...) {
            break;
        }
    }
    return result;
}

CommandType SpectrProtocol::commandTypeFromString(const std::string& cmd) {
    std::string upper = cmd;
    std::transform(upper.begin(), upper.end(), upper.begin(), ::toupper);
    
    if (upper == "GET_STAT")   return CommandType::GET_STAT;
    if (upper == "GET_REFER")  return CommandType::GET_REFER;
    if (upper == "GET_CONFIG") return CommandType::GET_CONFIG;
    if (upper == "GET_DATE")   return CommandType::GET_DATE;
    if (upper == "SET_PHASE")  return CommandType::SET_PHASE;
    if (upper == "SET_YF")     return CommandType::SET_YF;
    if (upper == "SET_OS")     return CommandType::SET_OS;
    if (upper == "SET_LOCAL")  return CommandType::SET_LOCAL;
    if (upper == "SET_START")  return CommandType::SET_START;
    if (upper == "SET_EVENT")  return CommandType::SET_EVENT;
    
    return CommandType::UNKNOWN;
}

std::string SpectrProtocol::formatEvent(uint16_t eventCounter, uint8_t eventType, 
                                        const std::vector<std::string>& params) {
    std::ostringstream ss;
    ss << "#" << getTime() << " EVENT (" << eventCounter << ") " << static_cast<int>(eventType);
    
    for (const auto& param : params) {
        ss << " " << param;
    }
    
    return appendChecksum(ss.str());
}

SpectrProtocol::ParsedCommand SpectrProtocol::parseCommand(const std::string& data) {
    ParsedCommand result;
    result.rawData = data;
    
    if (data.empty()) {
        result.error = SpectrError::UNINDENT;
        LOG_DEBUG("Empty command received");
        return result;
    }
    
    // Удаляем trailing whitespace
    std::string cleanData = data;
    while (!cleanData.empty() && (cleanData.back() == '\r' || cleanData.back() == '\n' || cleanData.back() == ' ')) {
        cleanData.pop_back();
    }
    
    if (cleanData.empty()) {
        result.error = SpectrError::UNINDENT;
        return result;
    }
    
    if (cleanData[0] == '#') {
        return parseChecksumCommand(cleanData);
    } else if (cleanData[0] == '!') {
        return parseSimpleCommand(cleanData);
    } else {
        result.error = SpectrError::UNINDENT;
        LOG_DEBUG("Invalid command prefix: ", cleanData[0]);
        return result;
    }
}

SpectrProtocol::ParsedCommand SpectrProtocol::parseChecksumCommand(const std::string& data) {
    ParsedCommand result;
    result.rawData = data;
    
    // Формат: "#TIME COMMAND REQUEST_ID PARAMS...$XX"
    size_t dollarPos = data.find_last_of('$');
    if (dollarPos == std::string::npos || data.length() < dollarPos + 3) {
        result.error = SpectrError::BAD_CHECK;
        LOG_DEBUG("Missing checksum in command");
        return result;
    }
    
    // Проверка контрольной суммы
    std::string dataWithoutChecksum = data.substr(0, dollarPos);
    std::string checksumStr = data.substr(dollarPos + 1, 2);
    
    try {
        uint8_t receivedChecksum = static_cast<uint8_t>(std::stoi(checksumStr, nullptr, 16));
        uint8_t calculatedChecksum = checksum(dataWithoutChecksum);
        
        if (receivedChecksum != calculatedChecksum) {
            result.error = SpectrError::BAD_CHECK;
            LOG_DEBUG("Checksum mismatch: received=", std::hex, (int)receivedChecksum, 
                     " calculated=", (int)calculatedChecksum);
            return result;
        }
    } catch (const std::exception& e) {
        result.error = SpectrError::BAD_CHECK;
        LOG_DEBUG("Invalid checksum format: ", e.what());
        return result;
    }
    
    // Парсинг команды (пропускаем '#')
    std::istringstream iss(dataWithoutChecksum.substr(1));
    std::string time, command;
    
    iss >> time >> command;
    
    if (command.empty()) {
        result.error = SpectrError::BAD_DATA;
        return result;
    }
    
    result.command = command;
    std::transform(result.command.begin(), result.command.end(), 
                   result.command.begin(), ::toupper);
    result.type = commandTypeFromString(result.command);
    
    // Читаем requestId
    std::string token;
    if (iss >> token) {
        result.requestId = token;
        
        // Читаем остальные параметры
        while (iss >> token) {
            result.params.push_back(token);
        }
    }
    
    result.isValid = true;
    result.error = SpectrError::OK;
    
    LOG_TRACE("Parsed command: ", result.command, " requestId=", result.requestId, 
             " params=", result.params.size());
    
    return result;
}

SpectrProtocol::ParsedCommand SpectrProtocol::parseSimpleCommand(const std::string& data) {
    ParsedCommand result;
    result.rawData = data;
    
    // Формат: "!TIME COMMAND PARAMS..."
    std::istringstream iss(data.substr(1)); // Пропускаем '!'
    std::string time, command;
    
    iss >> time >> command;
    
    if (command.empty()) {
        result.error = SpectrError::BAD_DATA;
        return result;
    }
    
    result.command = command;
    std::transform(result.command.begin(), result.command.end(), 
                   result.command.begin(), ::toupper);
    result.type = commandTypeFromString(result.command);
    
    // Читаем параметры
    std::string token;
    while (iss >> token) {
        result.params.push_back(token);
    }
    
    result.isValid = true;
    result.error = SpectrError::OK;
    
    return result;
}
