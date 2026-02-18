// Простой тест SNMP подключения для проверки без полной сборки проекта
// Компиляция: g++ -o test_simple_connect test_simple_connect.cpp -lsnmp -lpthread

#include <iostream>
#include <string>
#include <cstring>
#include <netinet/in.h>

// Проверка доступности net-snmp заголовков
#ifdef __has_include
    #if __has_include(<netsnmp/session_api.h>)
        #include <netsnmp/session_api.h>
        #include <netsnmp/pdu_api.h>
        #include <netsnmp/snmp_api.h>
        #define HAVE_NETSNMP 1
    #else
        #define HAVE_NETSNMP 0
    #endif
#else
    // Fallback для старых компиляторов
    #include <netsnmp/session_api.h>
    #include <netsnmp/pdu_api.h>
    #include <netsnmp/snmp_api.h>
    #define HAVE_NETSNMP 1
#endif

int main(int argc, char* argv[]) {
    std::string address = "192.168.75.150";
    std::string community = "UTMC";
    
    if (argc >= 2) {
        address = argv[1];
    }
    if (argc >= 3) {
        community = argv[2];
    }
    
    std::cout << "=== Простой тест SNMP подключения ===" << std::endl;
    std::cout << "Контроллер: " << address << std::endl;
    std::cout << "SNMP community: " << community << std::endl;
    std::cout << std::endl;
    
#if HAVE_NETSNMP
    std::cout << "1. Инициализация SNMP..." << std::endl;
    init_snmp("test_simple_connect");
    
    std::cout << "2. Создание SNMP-сессии..." << std::endl;
    netsnmp_session session;
    snmp_sess_init(&session);
    session.peername = strdup(address.c_str());
    session.version = SNMP_VERSION_2c;
    session.community = reinterpret_cast<u_char*>(strdup(community.c_str()));
    session.community_len = community.length();
    session.timeout = 5000000; // 5 секунд
    session.retries = 3;
    
    netsnmp_session* ss = snmp_open(&session);
    if (ss == nullptr) {
        std::cerr << "ОШИБКА: не удалось создать SNMP-сессию" << std::endl;
        std::cerr << "  Проверьте: IP адрес, SNMP community, доступность по сети" << std::endl;
        return 1;
    }
    
    std::cout << "   OK: сессия создана" << std::endl;
    
    std::cout << std::endl << "3. Проверка GET: sysUpTime (1.3.6.1.2.1.1.3.0)..." << std::endl;
    
    netsnmp_pdu* pdu = snmp_pdu_create(SNMP_MSG_GET);
    if (pdu == nullptr) {
        std::cerr << "ОШИБКА: не удалось создать PDU" << std::endl;
        snmp_close(ss);
        return 1;
    }
    
    oid oidBuf[MAX_OID_LEN];
    size_t oidLen = MAX_OID_LEN;
    if (!snmp_parse_oid("1.3.6.1.2.1.1.3.0", oidBuf, &oidLen)) {
        std::cerr << "ОШИБКА: не удалось распарсить OID" << std::endl;
        snmp_free_pdu(pdu);
        snmp_close(ss);
        return 1;
    }
    
    snmp_add_null_var(pdu, oidBuf, oidLen);
    
    netsnmp_pdu* response = nullptr;
    int status = snmp_sess_sync_response(ss, pdu, &response);
    
    if (status != STAT_SUCCESS || response == nullptr) {
        std::cerr << "ОШИБКА: запрос GET не выполнен" << std::endl;
        if (status == STAT_TIMEOUT) {
            std::cerr << "  Причина: таймаут" << std::endl;
        } else {
            std::cerr << "  Причина: " << snmp_errstring(status) << std::endl;
        }
        if (pdu) snmp_free_pdu(pdu);
        if (response) snmp_free_pdu(response);
        snmp_close(ss);
        return 1;
    }
    
    if (response->errstat != SNMP_ERR_NOERROR) {
        std::cerr << "ОШИБКА: SNMP ошибка в ответе: " << snmp_errstring(response->errstat) << std::endl;
        std::cerr << "  Код ошибки: " << response->errstat << std::endl;
        if (response->errstat == SNMP_ERR_NOSUCHNAME) {
            std::cerr << "  OID может не существовать или SNMP community задан неверно" << std::endl;
        } else if (response->errstat == SNMP_ERR_AUTHORIZATIONERROR) {
            std::cerr << "  Ошибка авторизации: проверьте SNMP community" << std::endl;
        }
        snmp_free_pdu(response);
        snmp_close(ss);
        return 1;
    }
    
    std::cout << "   OK: получен ответ" << std::endl;
    
    for (netsnmp_variable_list* vars = response->variables; vars != nullptr; vars = vars->next_variable) {
        char oidBuf[1024];
        snprint_objid(oidBuf, sizeof(oidBuf), vars->name, vars->name_length);
        
        char valueBuf[1024];
        snprint_value(valueBuf, sizeof(valueBuf), vars->name, vars->name_length, vars);
        
        std::cout << "   OID: " << oidBuf << std::endl;
        std::cout << "   Значение: " << valueBuf << std::endl;
    }
    
    snmp_free_pdu(response);
    snmp_close(ss);
    
    std::cout << std::endl << "=== Тест завершен успешно ===" << std::endl;
    return 0;
#else
    std::cerr << "ОШИБКА: заголовки net-snmp не найдены" << std::endl;
    std::cerr << "Установка: sudo apt-get install libsnmp-dev" << std::endl;
    return 1;
#endif
}
