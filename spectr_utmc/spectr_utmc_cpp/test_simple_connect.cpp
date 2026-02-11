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
    
    std::cout << "=== Simple SNMP Connection Test ===" << std::endl;
    std::cout << "Controller: " << address << std::endl;
    std::cout << "Community: " << community << std::endl;
    std::cout << std::endl;
    
#if HAVE_NETSNMP
    std::cout << "1. Initializing SNMP..." << std::endl;
    init_snmp("test_simple_connect");
    
    std::cout << "2. Creating SNMP session..." << std::endl;
    netsnmp_session session;
    snmp_sess_init(&session);
    session.peername = strdup(address.c_str());
    session.version = SNMP_VERSION_2c;
    session.community = reinterpret_cast<u_char*>(strdup(community.c_str()));
    session.community_len = community.length();
    session.timeout = 5000000; // 5 seconds
    session.retries = 3;
    
    netsnmp_session* ss = snmp_open(&session);
    if (ss == nullptr) {
        std::cerr << "ERROR: Failed to create SNMP session" << std::endl;
        std::cerr << "  Check: IP address, community string, network connectivity" << std::endl;
        return 1;
    }
    
    std::cout << "   OK: Session created successfully" << std::endl;
    
    std::cout << std::endl << "3. Testing GET: sysUpTime (1.3.6.1.2.1.1.3.0)..." << std::endl;
    
    netsnmp_pdu* pdu = snmp_pdu_create(SNMP_MSG_GET);
    if (pdu == nullptr) {
        std::cerr << "ERROR: Failed to create PDU" << std::endl;
        snmp_close(ss);
        return 1;
    }
    
    oid oidBuf[MAX_OID_LEN];
    size_t oidLen = MAX_OID_LEN;
    if (!snmp_parse_oid("1.3.6.1.2.1.1.3.0", oidBuf, &oidLen)) {
        std::cerr << "ERROR: Failed to parse OID" << std::endl;
        snmp_free_pdu(pdu);
        snmp_close(ss);
        return 1;
    }
    
    snmp_add_null_var(pdu, oidBuf, oidLen);
    
    netsnmp_pdu* response = nullptr;
    int status = snmp_sess_sync_response(ss, pdu, &response);
    
    if (status != STAT_SUCCESS || response == nullptr) {
        std::cerr << "ERROR: GET request failed" << std::endl;
        if (status == STAT_TIMEOUT) {
            std::cerr << "  Reason: Timeout" << std::endl;
        } else {
            std::cerr << "  Reason: " << snmp_errstring(status) << std::endl;
        }
        if (pdu) snmp_free_pdu(pdu);
        if (response) snmp_free_pdu(response);
        snmp_close(ss);
        return 1;
    }
    
    if (response->errstat != SNMP_ERR_NOERROR) {
        std::cerr << "ERROR: SNMP error in response: " << snmp_errstring(response->errstat) << std::endl;
        std::cerr << "  Error code: " << response->errstat << std::endl;
        if (response->errstat == SNMP_ERR_NOSUCHNAME) {
            std::cerr << "  OID may not exist or community string may be incorrect" << std::endl;
        } else if (response->errstat == SNMP_ERR_AUTHORIZATIONERROR) {
            std::cerr << "  Authorization error - check community string" << std::endl;
        }
        snmp_free_pdu(response);
        snmp_close(ss);
        return 1;
    }
    
    std::cout << "   OK: Received response" << std::endl;
    
    for (netsnmp_variable_list* vars = response->variables; vars != nullptr; vars = vars->next_variable) {
        char oidBuf[1024];
        snprint_objid(oidBuf, sizeof(oidBuf), vars->name, vars->name_length);
        
        char valueBuf[1024];
        snprint_value(valueBuf, sizeof(valueBuf), vars->name, vars->name_length, vars);
        
        std::cout << "   OID: " << oidBuf << std::endl;
        std::cout << "   Value: " << valueBuf << std::endl;
    }
    
    snmp_free_pdu(response);
    snmp_close(ss);
    
    std::cout << std::endl << "=== Test completed successfully ===" << std::endl;
    return 0;
#else
    std::cerr << "ERROR: net-snmp headers not found" << std::endl;
    std::cerr << "Please install: sudo apt-get install libsnmp-dev" << std::endl;
    return 1;
#endif
}
