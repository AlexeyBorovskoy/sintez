#include "snmp_handler.h"
#include <iostream>
#include <cstring>
#include <sstream>
#include <algorithm>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <errno.h>

SNMPHandler::SNMPHandler(const std::string& community)
    : community_(community), receiverRunning_(false), receiverSocket_(-1) {
    init_snmp("spectr_utmc_cpp");
}

SNMPHandler::~SNMPHandler() {
    stopReceiver();
    
    for (auto& pair : sessions_) {
        if (pair.second) {
            void* handle = reinterpret_cast<void*>(pair.second);
            snmp_sess_close(handle);
        }
    }
    sessions_.clear();
}

bool SNMPHandler::createSession(const std::string& address, const std::string& community) {
    if (sessions_.find(address) != sessions_.end()) {
        return true; // Сессия уже существует
    }
    
    netsnmp_session session;
    snmp_sess_init(&session);
    session.peername = strdup(address.c_str());
    session.version = SNMP_VERSION_2c;
    session.community = reinterpret_cast<u_char*>(strdup(community.c_str()));
    session.community_len = community.length();
    
    // Установка таймаута: 5 секунд для запросов
    session.timeout = 5000000; // микросекунды (5 секунд)
    session.retries = 3; // Количество повторов
    
    void* handle = snmp_sess_open(&session);
    if (handle == nullptr) {
        std::cerr << "Failed to create SNMP session for " << address << std::endl;
        std::cerr << "  Check: IP address, community string, network connectivity" << std::endl;
        // Освобождаем память при ошибке
        free(session.peername);
        free(session.community);
        return false;
    }
    
    // Освобождаем память, так как snmp_sess_open создает копии
    free(session.peername);
    free(session.community);
    
    sessions_[address] = handle;
    return true;
}

bool SNMPHandler::startReceiver(uint16_t port, NotificationCallback callback) {
    if (receiverRunning_) {
        return false;
    }
    
    notificationCallback_ = callback;
    receiverRunning_ = true;
    receiverThread_ = std::thread(&SNMPHandler::receiverThread, this, port);
    return true;
}

void SNMPHandler::stopReceiver() {
    if (!receiverRunning_) {
        return;
    }
    
    receiverRunning_ = false;
    
    if (receiverSocket_ >= 0) {
        close(receiverSocket_);
        receiverSocket_ = -1;
    }
    
    if (receiverThread_.joinable()) {
        receiverThread_.join();
    }
}

void SNMPHandler::receiverThread(uint16_t port) {
    // Создаем UDP сокет для приема traps/informs
    int sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (sock < 0) {
        std::cerr << "Failed to create UDP socket: " << strerror(errno) << std::endl;
        receiverRunning_ = false;
        return;
    }
    
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons(port);
    
    if (bind(sock, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        std::cerr << "Failed to bind UDP socket to port " << port << ": " << strerror(errno) << std::endl;
        close(sock);
        receiverRunning_ = false;
        return;
    }
    
    receiverSocket_ = sock;
    std::cout << "SNMP receiver started on port " << port << std::endl;
    
    while (receiverRunning_) {
        fd_set readFds;
        FD_ZERO(&readFds);
        FD_SET(sock, &readFds);
        
        struct timeval timeout;
        timeout.tv_sec = 1;
        timeout.tv_usec = 0;
        
        int result = select(sock + 1, &readFds, nullptr, nullptr, &timeout);
        
        if (result > 0 && FD_ISSET(sock, &readFds)) {
            char buffer[4096];
            struct sockaddr_in fromAddr;
            socklen_t fromLen = sizeof(fromAddr);
            
            ssize_t bytesReceived = recvfrom(sock, buffer, sizeof(buffer), 0,
                                            (struct sockaddr*)&fromAddr, &fromLen);
            
            if (bytesReceived > 0) {
                // Парсим PDU из буфера
                netsnmp_pdu pdu;
                memset(&pdu, 0, sizeof(pdu));
                u_char* data = reinterpret_cast<u_char*>(buffer);
                size_t dataLen = bytesReceived;
                
                if (snmp_pdu_parse(&pdu, data, &dataLen) == 0) {
                    // Извлекаем адрес источника
                    char addrStr[INET_ADDRSTRLEN];
                    inet_ntop(AF_INET, &fromAddr.sin_addr, addrStr, INET_ADDRSTRLEN);
                    
                    // Создаем notification
                    SNMPNotification notification;
                    notification.sourceAddress = addrStr;
                    
                    // Обрабатываем varbinds
                    for (netsnmp_variable_list* vars = pdu.variables; vars != nullptr; vars = vars->next_variable) {
                        SNMPVarbind varbind;
                        
                        char oidBuf[1024];
                        snprint_objid(oidBuf, sizeof(oidBuf), vars->name, vars->name_length);
                        varbind.oid = oidBuf;
                        varbind.type = vars->type;
                        
                        char valueBuf[1024];
                        snprint_value(valueBuf, sizeof(valueBuf), vars->name, vars->name_length, vars);
                        varbind.value = valueBuf;
                        
                        notification.varbinds.push_back(varbind);
                    }
                    
                    if (notificationCallback_) {
                        notificationCallback_(notification);
                    }
                }
            } else if (bytesReceived < 0 && errno != EAGAIN && errno != EWOULDBLOCK) {
                std::cerr << "SNMP recvfrom error: " << strerror(errno) << std::endl;
            }
        }
    }
    
    close(sock);
    receiverSocket_ = -1;
}

void SNMPHandler::processNotification(netsnmp_pdu* pdu, netsnmp_transport* transport, void* context) {
    // Эта функция больше не используется напрямую, но оставлена для совместимости
    // Обработка traps теперь происходит напрямую в receiverThread
    (void)pdu;
    (void)transport;
    (void)context;
}

bool SNMPHandler::get(const std::string& address, const std::vector<std::string>& oids,
                      std::function<void(bool error, const std::vector<SNMPVarbind>&)> callback) {
    void* handle = getSession(address);
    if (handle == nullptr) {
        if (!createSession(address, community_)) {
            if (callback) callback(true, {});
            return false;
        }
        handle = getSession(address);
    }
    
    if (handle == nullptr) {
        if (callback) callback(true, {});
        return false;
    }
    
    netsnmp_pdu* pdu = snmp_pdu_create(SNMP_MSG_GET);
    if (pdu == nullptr) {
        if (callback) callback(true, {});
        return false;
    }
    
    for (const auto& oidStr : oids) {
        oid oidBuf[MAX_OID_LEN];
        size_t oidLen = MAX_OID_LEN;
        
        if (!snmp_parse_oid(oidStr.c_str(), oidBuf, &oidLen)) {
            snmp_free_pdu(pdu);
            if (callback) callback(true, {});
            return false;
        }
        
        snmp_add_null_var(pdu, oidBuf, oidLen);
    }
    
    netsnmp_pdu* response = nullptr;
    int status = snmp_sess_synch_response(handle, pdu, &response);
    
    std::vector<SNMPVarbind> varbinds;
    bool hasError = (status != STAT_SUCCESS || response == nullptr);
    
    // Детальная обработка ошибок
    if (hasError) {
        if (status == STAT_TIMEOUT) {
            std::cerr << "SNMP GET timeout for " << address << std::endl;
        } else if (status == STAT_ERROR) {
            std::cerr << "SNMP GET error for " << address << ": " << snmp_errstring(status) << std::endl;
        }
    }
    
    if (!hasError && response->errstat == SNMP_ERR_NOERROR) {
        for (netsnmp_variable_list* vars = response->variables; vars != nullptr; vars = vars->next_variable) {
            SNMPVarbind varbind;
            
            char oidBuf[1024];
            snprint_objid(oidBuf, sizeof(oidBuf), vars->name, vars->name_length);
            varbind.oid = oidBuf;
            varbind.type = vars->type;
            
            char valueBuf[1024];
            snprint_value(valueBuf, sizeof(valueBuf), vars->name, vars->name_length, vars);
            varbind.value = valueBuf;
            
            varbinds.push_back(varbind);
        }
    } else if (response != nullptr) {
        // Обработка ошибок в ответе SNMP
        if (response->errstat != SNMP_ERR_NOERROR) {
            std::cerr << "SNMP error in response: " << snmp_errstring(response->errstat) 
                      << " (code: " << response->errstat << ")" << std::endl;
            if (response->errstat == SNMP_ERR_NOSUCHNAME) {
                std::cerr << "  OID may not exist or community string may be incorrect" << std::endl;
            } else if (response->errstat == SNMP_ERR_AUTHORIZATIONERROR) {
                std::cerr << "  Authorization error - check community string" << std::endl;
            }
        }
        hasError = true;
    }
    
    if (response) {
        snmp_free_pdu(response);
    }
    
    if (callback) {
        callback(hasError, varbinds);
    }
    
    return !hasError;
}

bool SNMPHandler::set(const std::string& address, const std::vector<SNMPVarbind>& varbinds,
                      std::function<void(bool error, const std::vector<SNMPVarbind>&)> callback) {
    void* handle = getSession(address);
    if (handle == nullptr) {
        if (!createSession(address, community_)) {
            if (callback) callback(true, {});
            return false;
        }
        handle = getSession(address);
    }
    
    if (handle == nullptr) {
        if (callback) callback(true, {});
        return false;
    }
    
    netsnmp_pdu* pdu = snmp_pdu_create(SNMP_MSG_SET);
    if (pdu == nullptr) {
        if (callback) callback(true, {});
        return false;
    }
    
    for (const auto& varbind : varbinds) {
        oid oidBuf[MAX_OID_LEN];
        size_t oidLen = MAX_OID_LEN;
        
        if (!snmp_parse_oid(varbind.oid.c_str(), oidBuf, &oidLen)) {
            snmp_free_pdu(pdu);
            if (callback) callback(true, {});
            return false;
        }
        
        // Определение типа и значения
        if (varbind.type == ASN_INTEGER) {
            long intValue = std::stol(varbind.value);
            snmp_pdu_add_variable(pdu, oidBuf, oidLen, ASN_INTEGER, &intValue, sizeof(intValue));
        } else if (varbind.type == ASN_OCTET_STR) {
            snmp_pdu_add_variable(pdu, oidBuf, oidLen, ASN_OCTET_STR, 
                                 const_cast<char*>(varbind.value.c_str()), varbind.value.length());
        } else {
            // Для других типов нужна дополнительная обработка
            snmp_free_pdu(pdu);
            if (callback) callback(true, {});
            return false;
        }
    }
    
    netsnmp_pdu* response = nullptr;
    int status = snmp_sess_synch_response(handle, pdu, &response);
    
    std::vector<SNMPVarbind> resultVarbinds;
    bool hasError = (status != STAT_SUCCESS || response == nullptr);
    
    if (!hasError && response->errstat == SNMP_ERR_NOERROR) {
        for (netsnmp_variable_list* vars = response->variables; vars != nullptr; vars = vars->next_variable) {
            SNMPVarbind varbind;
            
            char oidBuf[1024];
            snprint_objid(oidBuf, sizeof(oidBuf), vars->name, vars->name_length);
            varbind.oid = oidBuf;
            varbind.type = vars->type;
            
            char valueBuf[1024];
            snprint_value(valueBuf, sizeof(valueBuf), vars->name, vars->name_length, vars);
            varbind.value = valueBuf;
            
            resultVarbinds.push_back(varbind);
        }
    } else {
        hasError = true;
    }
    
    if (response) {
        snmp_free_pdu(response);
    }
    
    if (callback) {
        callback(hasError, resultVarbinds);
    }
    
    return !hasError;
}

void* SNMPHandler::getSession(const std::string& address) {
    auto it = sessions_.find(address);
    if (it != sessions_.end()) {
        return it->second;
    }
    return nullptr;
}
