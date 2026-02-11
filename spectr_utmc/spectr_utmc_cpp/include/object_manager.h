#ifndef OBJECT_MANAGER_H
#define OBJECT_MANAGER_H

#include "config.h"
#include "snmp_handler.h"
#include "tcp_client.h"
#include "spectr_protocol.h"
#include <string>
#include <map>
#include <atomic>
#include <cstdint>

struct ObjectState {
    uint8_t damage = 0;
    uint8_t error = 0;
    uint8_t units = 0;
    uint8_t unitsGood = 0;
    uint8_t powerFlags = 0;
    uint8_t controlSource = 255;
    uint8_t algorithm = 255;
    uint8_t plan = 255;
    uint16_t cicleCounter = 0;
    uint8_t stage = 255;
    uint8_t stageLen = 255;
    uint16_t stageCounter = 0;
    uint8_t transition = 0;
    uint8_t regime = 255;
    uint8_t testMode = 0;
    uint8_t syncError = 0;
    uint8_t dynamicFlags = 0;
};

class SpectrObject {
public:
    SpectrObject(const ObjectConfig& config, const std::string& community, SNMPHandler* snmpHandler, TcpClient* tcpClient);
    ~SpectrObject();
    
    // Обработка SNMP notification
    void processNotification(const SNMPNotification& notification);
    
    // Обработка команды от ITS сервера
    void processCommand(const SpectrProtocol::ParsedCommand& command);
    
    // Отправка события
    void sendEvent(uint8_t eventType, const std::vector<std::string>& params);
    
    // Обновление состояния
    void updateState();
    
    // Изменение состояния
    void changeState(const std::map<std::string, uint8_t>& changes);
    
    // Команды SET
    SpectrError setPhase(const std::string& requestId, uint8_t phase);
    SpectrError setYF(const std::string& requestId);
    SpectrError setOS(const std::string& requestId);
    SpectrError setLocal(const std::string& requestId);
    SpectrError setStart(const std::string& requestId);
    
    // Команды GET
    std::string getStat(const std::string& requestId);
    std::string getRefer(const std::string& requestId);
    std::string getConfig(const std::string& requestId, uint32_t param1, uint32_t param2);
    std::string getDate(const std::string& requestId);
    
    // Получение состояния
    const ObjectState& getState() const { return state_; }
    uint32_t getId() const { return config_.id; }
    std::string getAddress() const { return config_.addr; }

private:
    ObjectConfig config_;
    std::string community_;
    ObjectState state_;
    SNMPHandler* snmpHandler_;
    TcpClient* tcpClient_;
    
    std::atomic<uint16_t> eventCounter_;
    std::atomic<uint16_t> eventMask_;
    
    int64_t stageStartTime_;
    int64_t cycleStartTime_;
    
    // Механизм удержания команды жёлтого мигания
    std::atomic<bool> yfHoldActive_;
    std::atomic<bool> yfStop_;
    std::thread yfHoldThread_;
    uint8_t savedOperationMode_;  // Сохранённый режим работы для восстановления
    
    void processSNMPVarbind(const SNMPVarbind& varbind);
    void sendToITS(const std::string& data);
    void requestOperationMode();
    
    // Получение информации о текущей фазе
    struct PhaseInfo {
        uint8_t phase = 0;           // Номер фазы (1-7)
        uint16_t stageLength = 0;    // Длительность фазы (секунды)
        uint16_t stageCounter = 0;   // Счётчик текущей фазы (секунды)
        bool isValid = false;        // Валидность данных
    };
    PhaseInfo getCurrentPhaseInfo();
    bool isSpecialPhase(uint8_t phase);  // Проверка, является ли фаза специальной (1,2,3,4)
    
    // Механизм удержания команды SET_YF
    void startYFHold();
    void stopYFHold();
    void yfHoldThread();
    
    // Формирование OID с SCN для табличных объектов
    // Формат: BASE_OID.timestamp.SCN_ASCII_CODES
    std::string buildOIDWithSCN(const std::string& baseOID);
};

#endif // OBJECT_MANAGER_H
