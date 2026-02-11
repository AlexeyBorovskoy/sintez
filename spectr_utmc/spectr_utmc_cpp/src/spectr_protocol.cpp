#include "spectr_protocol.h"
#include <sstream>
#include <iomanip>
#include <ctime>
#include <algorithm>
#include <cctype>

uint8_t SpectrProtocol::checksum(const std::string& data) {
    uint16_t sum = 0;
    for (char c : data) {
        sum += static_cast<uint8_t>(c);
        if (sum & 0x100) {
            sum++;
        }
        if (sum & 0x80) {
            sum += sum;
            sum++;
        } else {
            sum += sum;
        }
        sum &= 0xFF;
    }
    return static_cast<uint8_t>(sum);
}

std::string SpectrProtocol::appendChecksum(const std::string& data) {
    uint8_t chk = checksum(data);
    std::stringstream ss;
    ss << data << "$" << std::hex << std::setw(2) << std::setfill('0') 
       << static_cast<int>(chk) << "\r";
    return ss.str();
}

std::string SpectrProtocol::formatResult(SpectrError error, const std::string& requestId) {
    std::string errorStr;
    std::string errorParam;
    switch (error) {
        case SpectrError::OK: errorStr = ">O.K."; break;
        case SpectrError::OFF_LINE: errorStr = ">OFF_LINE"; break;
        case SpectrError::BAD_CHECK: errorStr = ">BAD_CHECK"; break;
        case SpectrError::UNINDENT: errorStr = ">UNINDENT"; break;
        case SpectrError::BROKEN: errorStr = ">BROKEN"; break;
        case SpectrError::TOO_LONG: errorStr = ">TOO_LONG"; break;
        case SpectrError::BAD_DATA: errorStr = ">BAD_DATA"; break;
        case SpectrError::BAD_PARAM: errorStr = ">BAD_PARAM"; break;
        case SpectrError::NOT_EXEC_1: errorStr = ">NOT_EXEC"; errorParam = "1"; break;
        case SpectrError::NOT_EXEC_2: errorStr = ">NOT_EXEC"; errorParam = "2"; break;
        case SpectrError::NOT_EXEC_3: errorStr = ">NOT_EXEC"; errorParam = "3"; break;
        case SpectrError::NOT_EXEC_4: errorStr = ">NOT_EXEC"; errorParam = "4"; break;
        case SpectrError::NOT_EXEC_5: errorStr = ">NOT_EXEC"; errorParam = "5"; break;
        case SpectrError::NOT_EXEC_255: errorStr = ">NOT_EXEC"; errorParam = "255"; break;
    }

    if (requestId.empty()) {
        std::stringstream ss;
        ss << "!" << getTime() << " " << errorStr << " " << errorParam << "\r";
        return ss.str();
    }

    std::stringstream ss;
    ss << "#" << getTime() << " " << errorStr << " " << requestId << " " << errorParam;
    return appendChecksum(ss.str());
}

std::string SpectrProtocol::formatResult(SpectrError error, const std::string& requestId, const std::string& data) {
    if (error == SpectrError::OK) {
        std::stringstream ss;
        ss << "#" << getTime() << " >O.K. " << requestId << " " << data;
        return appendChecksum(ss.str());
    } else {
        return formatResult(error, requestId);
    }
}

std::string SpectrProtocol::getTime() {
    std::time_t now = std::time(nullptr);
    std::tm* local = std::localtime(&now);
    
    std::stringstream ss;
    ss << std::setfill('0') << std::setw(2) << local->tm_hour << ":"
       << std::setw(2) << local->tm_min << ":"
       << std::setw(2) << local->tm_sec;
    return ss.str();
}

std::string SpectrProtocol::toHex(const std::string& data) {
    std::stringstream ss;
    for (unsigned char c : data) {
        ss << std::hex << std::setw(2) << std::setfill('0') << static_cast<int>(c);
    }
    return ss.str();
}

SpectrProtocol::ParsedCommand SpectrProtocol::parseCommand(const std::string& data) {
    ParsedCommand result;
    result.isValid = false;
    
    if (data.empty()) {
        result.error = SpectrError::UNINDENT;
        return result;
    }
    
    // Команда начинается с '#' или '!'
    if (data[0] == '#') {
        // Команда с checksum: формат "#TIME COMMAND REQUEST_ID PARAMS...$XX\r"
        size_t dollarPos = data.find_last_of('$');
        if (dollarPos == std::string::npos || data.length() < dollarPos + 3) {
            result.error = SpectrError::BAD_CHECK;
            return result;
        }
        
        // Проверка checksum
        std::string dataWithoutChecksum = data.substr(0, dollarPos);
        std::string checksumStr = data.substr(dollarPos + 1, 2);
        uint8_t receivedChecksum = static_cast<uint8_t>(std::stoi(checksumStr, nullptr, 16));
        uint8_t calculatedChecksum = checksum(dataWithoutChecksum);
        
        if (receivedChecksum != calculatedChecksum) {
            result.error = SpectrError::BAD_CHECK;
            return result;
        }
        
        // Парсинг команды
        std::string cmdData = dataWithoutChecksum.substr(1); // Пропускаем '#'
        std::istringstream iss(cmdData);
        std::string time, command;
        iss >> time >> command;
        
        if (iss.good()) {
            std::string requestId;
            iss >> requestId;
            result.requestId = requestId;
        }
        
        result.command = command;
        std::string param;
        while (iss >> param) {
            result.params.push_back(param);
        }
        
        result.isValid = true;
        result.error = SpectrError::OK;
        
    } else if (data[0] == '!') {
        // Команда без checksum: формат "!TIME COMMAND PARAMS...\r"
        std::istringstream iss(data.substr(1));
        std::string time, command;
        iss >> time >> command;
        
        result.command = command;
        std::string param;
        while (iss >> param) {
            result.params.push_back(param);
        }
        
        result.isValid = true;
        result.error = SpectrError::OK;
    } else {
        result.error = SpectrError::UNINDENT;
    }
    
    // Преобразование команды в верхний регистр
    std::transform(result.command.begin(), result.command.end(), 
                   result.command.begin(), ::toupper);
    
    return result;
}

std::string SpectrProtocol::formatEvent(uint16_t eventCounter, uint8_t eventType, 
                                         const std::vector<std::string>& params) {
    std::stringstream ss;
    ss << "#" << getTime() << " EVENT (" << eventCounter << ") " << static_cast<int>(eventType);
    
    for (const auto& param : params) {
        ss << " " << param;
    }
    
    return appendChecksum(ss.str());
}
