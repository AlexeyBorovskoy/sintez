#ifndef SNMP_HANDLER_H
#define SNMP_HANDLER_H

#include <string>
#include <functional>
#include <map>
#include <vector>
#include <atomic>
#include <thread>
#include <netinet/in.h>

extern "C" {
#include <net-snmp/net-snmp-config.h>
#include <net-snmp/library/snmp_transport.h>
#include <net-snmp/library/snmp_client.h>
#include <net-snmp/session_api.h>
#include <net-snmp/pdu_api.h>
#include <net-snmp/varbind_api.h>
#include <net-snmp/output_api.h>
}

// OID константы из MIB
namespace SNMPOID {
    const std::string UTMC = "1.3.6.1.4.1.13267";
    const std::string UTC_REPLY_ENTRY = UTMC + ".3.2.5.1.1";
    const std::string UTC_REPLY_GN = UTC_REPLY_ENTRY + ".3";
    const std::string UTC_REPLY_GN_1 = UTC_REPLY_GN + ".1";
    const std::string UTC_REPLY_FR = UTC_REPLY_ENTRY + ".36";
    const std::string UTC_REPLY_REGIME_OFF = UTC_REPLY_ENTRY + ".45";
    const std::string UTC_REPLY_STAGE_LENGTH = UTC_REPLY_ENTRY + ".4";  // Длительность фазы
    const std::string UTC_REPLY_STAGE_COUNTER = UTC_REPLY_ENTRY + ".5"; // Счётчик фазы
    const std::string UTC_REPLY_TRANSITION = UTC_REPLY_ENTRY + ".7";   // Переходные процессы
    const std::string UTC_REPLY_BY_EXCEPTION = UTMC + ".3.2.6.1";
    const std::string UTC_TYPE2_OPERATION_MODE = UTMC + ".3.2.4.1";
    const std::string UTC_CONTROL_ENTRY = UTMC + ".3.2.4.2.1";
    const std::string UTC_CONTROL_FN = UTC_CONTROL_ENTRY + ".5";
    const std::string UTC_CONTROL_LO = UTC_CONTROL_ENTRY + ".11";
    const std::string UTC_CONTROL_FF = UTC_CONTROL_ENTRY + ".20";
    const std::string SYS_UP_TIME = "1.3.6.1.2.1.1.3.0";
    const std::string SNMP_TRAP_OID = "1.3.6.1.6.3.1.1.4.1.0";
}

struct SNMPVarbind {
    std::string oid;
    int type;
    std::string value;
};

struct SNMPNotification {
    std::string sourceAddress;
    std::vector<SNMPVarbind> varbinds;
};

class SNMPHandler {
public:
    using NotificationCallback = std::function<void(const SNMPNotification&)>;
    
    SNMPHandler(const std::string& community);
    ~SNMPHandler();
    
    // Инициализация SNMP сессии для контроллера
    bool createSession(const std::string& address, const std::string& community);
    
    // Запуск SNMP trap receiver
    bool startReceiver(uint16_t port, NotificationCallback callback);
    
    // Остановка receiver
    void stopReceiver();
    
    // SNMP GET операция
    bool get(const std::string& address, const std::vector<std::string>& oids, 
             std::function<void(bool error, const std::vector<SNMPVarbind>&)> callback);
    
    // SNMP SET операция
    bool set(const std::string& address, const std::vector<SNMPVarbind>& varbinds,
             std::function<void(bool error, const std::vector<SNMPVarbind>&)> callback);
    
    // Получение handle сессии для адреса
    void* getSession(const std::string& address);

private:
    std::string community_;
    std::map<std::string, void*> sessions_;
    
    std::atomic<bool> receiverRunning_;
    std::thread receiverThread_;
    NotificationCallback notificationCallback_;
    int receiverSocket_;
    
    void receiverThread(uint16_t port);
    static void processNotification(netsnmp_pdu* pdu, netsnmp_transport* transport, void* context);
    static int callbackFunction(int operation, netsnmp_session* session, 
                                int reqid, netsnmp_pdu* pdu, void* magic);
};

#endif // SNMP_HANDLER_H
