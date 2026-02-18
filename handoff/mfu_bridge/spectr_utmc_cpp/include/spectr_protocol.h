#ifndef SPECTR_PROTOCOL_H
#define SPECTR_PROTOCOL_H

#include <string>
#include <vector>
#include <cstdint>
#include <functional>

// Коды ошибок протокола Spectr-ITS
enum class SpectrError {
    OK,
    OFF_LINE,
    BAD_CHECK,
    UNINDENT,
    BROKEN,
    TOO_LONG,
    BAD_DATA,
    BAD_PARAM,
    NOT_EXEC_1,  // No priority
    NOT_EXEC_2,  // Incorrect parameters
    NOT_EXEC_3,  // Incorrect command
    NOT_EXEC_4,  // Execution not possible
    NOT_EXEC_5,  // Internal error
    NOT_EXEC_255 // TLC response timeout
};

class SpectrProtocol {
public:
    // Вычисление checksum для протокола Spectr-ITS
    static uint8_t checksum(const std::string& data);
    
    // Добавление checksum к сообщению
    static std::string appendChecksum(const std::string& data);
    
    // Форматирование ответа
    static std::string formatResult(SpectrError error, const std::string& requestId = "");
    
    // Форматирование ответа с данными
    static std::string formatResult(SpectrError error, const std::string& requestId, const std::string& data);
    
    // Получение текущего времени в формате протокола
    static std::string getTime();
    
    // Конвертация в hex строку
    static std::string toHex(const std::string& data);
    
    // Парсинг команды из потока
    struct ParsedCommand {
        bool isValid;
        std::string command;
        std::string requestId;
        std::vector<std::string> params;
        SpectrError error;
    };
    
    static ParsedCommand parseCommand(const std::string& data);
    
    // Форматирование события
    static std::string formatEvent(uint16_t eventCounter, uint8_t eventType, const std::vector<std::string>& params);
};

#endif // SPECTR_PROTOCOL_H
