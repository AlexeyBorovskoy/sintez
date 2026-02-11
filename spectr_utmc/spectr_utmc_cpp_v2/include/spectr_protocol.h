#ifndef SPECTR_PROTOCOL_H
#define SPECTR_PROTOCOL_H

#include <string>
#include <vector>
#include <cstdint>
#include <optional>

// Коды ошибок протокола Spectr-ITS
enum class SpectrError {
    OK = 0,
    OFF_LINE = 1,
    BAD_CHECK = 2,
    UNINDENT = 3,
    BROKEN = 4,
    TOO_LONG = 5,
    BAD_DATA = 6,
    BAD_PARAM = 7,
    NOT_EXEC_1 = 8,   // Неверный ID объекта
    NOT_EXEC_2 = 9,   // Команда не распознана
    NOT_EXEC_3 = 10,  // Неверная команда
    NOT_EXEC_4 = 11,  // Команда неприменима
    NOT_EXEC_5 = 12,  // Внутренняя ошибка
    NOT_EXEC_255 = 13 // Не выполнено
};

// Типы команд Spectr-ITS
enum class CommandType {
    UNKNOWN,
    GET_STAT,
    GET_REFER,
    GET_CONFIG,
    GET_DATE,
    SET_PHASE,
    SET_YF,
    SET_OS,
    SET_LOCAL,
    SET_START,
    SET_EVENT
};

class SpectrProtocol {
public:
    // Результат парсинга команды
    struct ParsedCommand {
        bool isValid = false;
        SpectrError error = SpectrError::OK;
        CommandType type = CommandType::UNKNOWN;
        std::string command;
        std::string requestId;
        std::vector<std::string> params;
        std::string rawData;
    };
    
    // Контекст для форматирования ответа
    struct ResponseContext {
        uint32_t objectId = 0;
        std::string requestId;
    };

    // Расчёт контрольной суммы (алгоритм из оригинального Node.js)
    static uint8_t checksum(const std::string& data);
    
    // Проверка контрольной суммы
    static bool verifyChecksum(const std::string& data);
    
    // Добавление контрольной суммы к данным
    static std::string appendChecksum(const std::string& data);
    
    // Форматирование результата команды
    static std::string formatResult(SpectrError error, const std::string& requestId);
    static std::string formatResult(SpectrError error, const std::string& requestId, const std::string& data);
    
    // Форматирование события
    static std::string formatEvent(uint16_t eventCounter, uint8_t eventType, 
                                   const std::vector<std::string>& params);
    
    // Парсинг входящей команды
    static ParsedCommand parseCommand(const std::string& data);
    
    // Получение текущего времени в формате HH:MM:SS
    static std::string getTime();
    
    // Преобразование строки в hex
    static std::string toHex(const std::string& data);
    
    // Преобразование hex в строку
    static std::string fromHex(const std::string& hex);
    
    // Получение строкового представления ошибки
    static const char* errorToString(SpectrError error);
    
    // Определение типа команды по строке
    static CommandType commandTypeFromString(const std::string& cmd);

private:
    // Парсинг команды с контрольной суммой (#...)
    static ParsedCommand parseChecksumCommand(const std::string& data);
    
    // Парсинг команды без контрольной суммы (!...)
    static ParsedCommand parseSimpleCommand(const std::string& data);
};

#endif // SPECTR_PROTOCOL_H
