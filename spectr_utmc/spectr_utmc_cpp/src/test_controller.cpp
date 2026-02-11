#include "snmp_handler.h"
#include "config.h"
#include <iostream>
#include <iomanip>
#include <thread>
#include <chrono>
#include <signal.h>

extern "C" {
#include <net-snmp/library/asn1.h>
}

static bool running = true;

void signalHandler(int signal) {
    std::cout << "\nReceived signal " << signal << ", shutting down..." << std::endl;
    running = false;
}

void printVarbind(const SNMPVarbind& vb, int index = -1) {
    std::cout << "  ";
    if (index >= 0) {
        std::cout << "[" << index << "] ";
    }
    std::cout << "OID: " << std::setw(50) << std::left << vb.oid;
    std::cout << " Type: " << std::setw(15) << vb.type;
    std::cout << " Value: " << vb.value << std::endl;
}

void testBasicConnectivity(SNMPHandler& handler, const std::string& address, const std::string& community) {
    std::cout << "\n=== Testing Basic Connectivity ===" << std::endl;
    std::cout << "Address: " << address << std::endl;
    std::cout << "Community: " << community << std::endl;
    
    // Создание сессии
    std::cout << "\n1. Creating SNMP session..." << std::endl;
    if (!handler.createSession(address, community)) {
        std::cerr << "ERROR: Failed to create SNMP session" << std::endl;
        return;
    }
    std::cout << "   OK: Session created successfully" << std::endl;
    
    // Тест 1: Получение системного времени работы (sysUpTime)
    std::cout << "\n2. Testing GET: sysUpTime (1.3.6.1.2.1.1.3.0)..." << std::endl;
    std::vector<std::string> oids1 = {"1.3.6.1.2.1.1.3.0"};
    bool success1 = handler.get(address, oids1, [](bool error, const std::vector<SNMPVarbind>& varbinds) {
        if (error) {
            std::cerr << "   ERROR: GET failed (see error messages above)" << std::endl;
        } else {
            std::cout << "   OK: Received " << varbinds.size() << " varbind(s)" << std::endl;
            for (size_t i = 0; i < varbinds.size(); ++i) {
                printVarbind(varbinds[i], i);
            }
        }
    });
    
    if (!success1) {
        std::cerr << "   ERROR: GET request failed" << std::endl;
    }
    
    // Небольшая задержка между запросами
    std::this_thread::sleep_for(std::chrono::milliseconds(500));
    
    // Тест 2: Получение версии приложения
    std::cout << "\n3. Testing GET: Application Version (1.3.6.1.4.1.13267.3.2.1.2)..." << std::endl;
    std::vector<std::string> oids2 = {"1.3.6.1.4.1.13267.3.2.1.2"};
    bool success2 = handler.get(address, oids2, [](bool error, const std::vector<SNMPVarbind>& varbinds) {
        if (error) {
            std::cerr << "   ERROR: GET failed (see error messages above)" << std::endl;
        } else {
            std::cout << "   OK: Received " << varbinds.size() << " varbind(s)" << std::endl;
            for (size_t i = 0; i < varbinds.size(); ++i) {
                printVarbind(varbinds[i], i);
            }
        }
    });
    
    if (!success2) {
        std::cerr << "   ERROR: GET request failed" << std::endl;
    }
    
    std::this_thread::sleep_for(std::chrono::milliseconds(500));
    
    // Тест 3: Получение режима работы
    std::cout << "\n4. Testing GET: Operation Mode (1.3.6.1.4.1.13267.3.2.4.1)..." << std::endl;
    // ВАЖНО: Этот контроллер требует OID БЕЗ .0 (в отличие от стандарта SNMP)
    std::vector<std::string> oids3 = {SNMPOID::UTC_TYPE2_OPERATION_MODE};
    bool success3 = handler.get(address, oids3, [](bool error, const std::vector<SNMPVarbind>& varbinds) {
        if (error) {
            std::cerr << "   ERROR: GET failed (see error messages above)" << std::endl;
        } else {
            std::cout << "   OK: Received " << varbinds.size() << " varbind(s)" << std::endl;
            for (size_t i = 0; i < varbinds.size(); ++i) {
                printVarbind(varbinds[i], i);
                if (!varbinds[i].value.empty()) {
                    // Парсим значение из формата "INTEGER: 1" или просто "1"
                    std::string valueStr = varbinds[i].value;
                    // Извлекаем число из строки вида "INTEGER: 1"
                    size_t colonPos = valueStr.find(':');
                    if (colonPos != std::string::npos) {
                        valueStr = valueStr.substr(colonPos + 1);
                    }
                    // Убираем пробелы
                    valueStr.erase(0, valueStr.find_first_not_of(" \t"));
                    valueStr.erase(valueStr.find_last_not_of(" \t") + 1);
                    
                    try {
                        int mode = std::stoi(valueStr);
                        std::cout << "      Mode: ";
                        switch (mode) {
                            case 1: std::cout << "Standalone"; break;
                            case 2: std::cout << "Monitor"; break;
                            case 3: std::cout << "UTC Control"; break;
                            default: std::cout << "Unknown (" << mode << ")"; break;
                        }
                        std::cout << std::endl;
                    } catch (...) {
                        std::cout << "      Mode: Unable to parse (value: \"" << varbinds[i].value << "\")" << std::endl;
                    }
                }
            }
        }
    });
    
    if (!success3) {
        std::cerr << "   ERROR: GET request failed" << std::endl;
    }
    
    std::this_thread::sleep_for(std::chrono::milliseconds(500));
    
    // Тест 4: Получение времени контроллера
    std::cout << "\n5. Testing GET: Controller Time (1.3.6.1.4.1.13267.3.2.3.2)..." << std::endl;
    // ВАЖНО: Этот контроллер требует OID БЕЗ .0 (в отличие от стандарта SNMP)
    std::vector<std::string> oids4 = {"1.3.6.1.4.1.13267.3.2.3.2"};
    bool success4 = handler.get(address, oids4, [](bool error, const std::vector<SNMPVarbind>& varbinds) {
        if (error) {
            std::cerr << "   ERROR: GET failed (see error messages above)" << std::endl;
        } else {
            std::cout << "   OK: Received " << varbinds.size() << " varbind(s)" << std::endl;
            for (size_t i = 0; i < varbinds.size(); ++i) {
                printVarbind(varbinds[i], i);
            }
        }
    });
    
    if (!success4) {
        std::cerr << "   ERROR: GET request failed" << std::endl;
    }
    
    std::cout << "\n=== Basic Connectivity Test Complete ===" << std::endl;
}

void testTrapReceiver(SNMPHandler& handler, uint16_t port) {
    std::cout << "\n=== Testing Trap Receiver ===" << std::endl;
    std::cout << "Listening on port " << port << "..." << std::endl;
    std::cout << "Press Ctrl+C to stop" << std::endl;
    
    bool received = false;
    
    auto callback = [&received](const SNMPNotification& notification) {
        received = true;
        std::cout << "\n>>> TRAP RECEIVED <<<" << std::endl;
        std::cout << "Source: " << notification.sourceAddress << std::endl;
        std::cout << "Varbinds: " << notification.varbinds.size() << std::endl;
        
        for (size_t i = 0; i < notification.varbinds.size(); ++i) {
            printVarbind(notification.varbinds[i], i);
        }
        std::cout << std::endl;
    };
    
    if (!handler.startReceiver(port, callback)) {
        std::cerr << "ERROR: Failed to start trap receiver" << std::endl;
        return;
    }
    
    std::cout << "Trap receiver started. Waiting for traps..." << std::endl;
    
    int timeout = 30; // секунды
    int elapsed = 0;
    
    while (running && elapsed < timeout) {
        std::this_thread::sleep_for(std::chrono::seconds(1));
        elapsed++;
        if (elapsed % 5 == 0) {
            std::cout << "Waiting... (" << elapsed << "/" << timeout << "s)" << std::endl;
        }
    }
    
    handler.stopReceiver();
    
    if (!received) {
        std::cout << "\nNo traps received within " << timeout << " seconds" << std::endl;
        std::cout << "This is normal if the controller is not sending traps" << std::endl;
    }
    
    std::cout << "\n=== Trap Receiver Test Complete ===" << std::endl;
}

void testWalkOID(SNMPHandler& handler, const std::string& address, const std::string& community, const std::string& oidPrefix) {
    std::cout << "\n=== Testing WALK: " << oidPrefix << " ===" << std::endl;
    std::cout << "⚠️  WARNING: This will perform multiple GET operations!" << std::endl;

    oid rootOid[MAX_OID_LEN];
    size_t rootLen = MAX_OID_LEN;
    if (!snmp_parse_oid(oidPrefix.c_str(), rootOid, &rootLen)) {
        std::cerr << "ERROR: Invalid OID prefix" << std::endl;
        return;
    }

    // Initialize session
    if (!handler.createSession(address, community)) {
        std::cerr << "ERROR: Failed to create SNMP session" << std::endl;
        return;
    }

    void* handle = handler.getSession(address);
    if (!handle) {
        std::cerr << "ERROR: No SNMP session handle" << std::endl;
        return;
    }

    oid currentOid[MAX_OID_LEN];
    size_t currentLen = rootLen;
    memcpy(currentOid, rootOid, rootLen * sizeof(oid));

    int maxSteps = 200;
    int steps = 0;

    while (steps < maxSteps) {
        netsnmp_pdu* pdu = snmp_pdu_create(SNMP_MSG_GETNEXT);
        if (!pdu) {
            std::cerr << "ERROR: Failed to create PDU" << std::endl;
            break;
        }

        snmp_add_null_var(pdu, currentOid, currentLen);

        netsnmp_pdu* response = nullptr;
        int status = snmp_sess_synch_response(handle, pdu, &response);

        if (status != STAT_SUCCESS || response == nullptr) {
            std::cerr << "ERROR: GETNEXT failed (status=" << status << ")" << std::endl;
            if (response) snmp_free_pdu(response);
            break;
        }

        if (response->errstat != SNMP_ERR_NOERROR || response->variables == nullptr) {
            std::cerr << "ERROR: GETNEXT response error (errstat=" << response->errstat << ")" << std::endl;
            snmp_free_pdu(response);
            break;
        }

        netsnmp_variable_list* vars = response->variables;

        // Check if still under root (prefix match)
        if (vars->name_length < rootLen ||
            snmp_oid_compare(rootOid, rootLen, vars->name, rootLen) != 0) {
            if (steps == 0) {
                char firstOidBuf[1024];
                snprint_objid(firstOidBuf, sizeof(firstOidBuf), vars->name, vars->name_length);
                std::cerr << "Walk stopped: first OID outside subtree: " << firstOidBuf << std::endl;
            }
            snmp_free_pdu(response);
            break;
        }

        SNMPVarbind varbind;
        char oidBuf[1024];
        snprint_objid(oidBuf, sizeof(oidBuf), vars->name, vars->name_length);
        varbind.oid = oidBuf;
        varbind.type = vars->type;

        char valueBuf[1024];
        snprint_value(valueBuf, sizeof(valueBuf), vars->name, vars->name_length, vars);
        varbind.value = valueBuf;

        printVarbind(varbind, steps);

        // Prepare next
        memcpy(currentOid, vars->name, vars->name_length * sizeof(oid));
        currentLen = vars->name_length;

        snmp_free_pdu(response);
        steps++;
    }

    std::cout << "=== WALK complete. Steps: " << steps << " ===" << std::endl;
}

void testGetOID(SNMPHandler& handler, const std::string& address, const std::string& oid) {
    std::cout << "\n=== Testing GET: " << oid << " ===" << std::endl;
    
    std::vector<std::string> oids = {oid};
    bool success = handler.get(address, oids, [](bool error, const std::vector<SNMPVarbind>& varbinds) {
        if (error) {
            std::cerr << "ERROR: GET failed" << std::endl;
        } else {
            std::cout << "OK: Received " << varbinds.size() << " varbind(s)" << std::endl;
            for (size_t i = 0; i < varbinds.size(); ++i) {
                printVarbind(varbinds[i], i);
            }
        }
    });
    
    if (!success) {
        std::cerr << "ERROR: GET request failed" << std::endl;
    }
}

void testSetOID(SNMPHandler& handler, const std::string& address, const std::string& oid, int type, const std::string& value) {
    std::cout << "\n=== Testing SET: " << oid << " ===" << std::endl;
    std::string typeName = (type == ASN_INTEGER) ? "INTEGER" : (type == ASN_OCTET_STR) ? "OCTET_STR" : "UNKNOWN";
    std::cout << "Type: " << type << " (" << typeName << "), Value: " << value << std::endl;
    std::cout << "⚠️  WARNING: This will modify controller state!" << std::endl;
    
    SNMPVarbind varbind;
    varbind.oid = oid;
    varbind.type = type;
    varbind.value = value;
    
    std::vector<SNMPVarbind> varbinds = {varbind};
    bool success = handler.set(address, varbinds, [](bool error, const std::vector<SNMPVarbind>& resultVarbinds) {
        if (error) {
            std::cerr << "ERROR: SET failed" << std::endl;
        } else {
            std::cout << "OK: SET operation completed" << std::endl;
            if (!resultVarbinds.empty()) {
                std::cout << "Response varbinds: " << resultVarbinds.size() << std::endl;
                for (size_t i = 0; i < resultVarbinds.size(); ++i) {
                    printVarbind(resultVarbinds[i], i);
                }
            }
        }
    });
    
    if (!success) {
        std::cerr << "ERROR: SET request failed" << std::endl;
    }
}

void testSetMultiple(SNMPHandler& handler, const std::string& address, const std::vector<std::tuple<std::string, int, std::string>>& varbindSpecs) {
    std::cout << "\n=== Testing SET (multiple varbinds) ===" << std::endl;
    std::cout << "⚠️  WARNING: This will modify controller state!" << std::endl;
    
    std::vector<SNMPVarbind> varbinds;
    for (const auto& spec : varbindSpecs) {
        SNMPVarbind varbind;
        varbind.oid = std::get<0>(spec);
        varbind.type = std::get<1>(spec);
        varbind.value = std::get<2>(spec);
        std::string typeName = (varbind.type == ASN_INTEGER) ? "INTEGER" : (varbind.type == ASN_OCTET_STR) ? "OCTET_STR" : "UNKNOWN";
        std::cout << "  OID: " << varbind.oid << ", Type: " << varbind.type << " (" << typeName << "), Value: " << varbind.value << std::endl;
        varbinds.push_back(varbind);
    }
    
    bool success = handler.set(address, varbinds, [](bool error, const std::vector<SNMPVarbind>& resultVarbinds) {
        if (error) {
            std::cerr << "ERROR: SET failed" << std::endl;
        } else {
            std::cout << "OK: SET operation completed" << std::endl;
            if (!resultVarbinds.empty()) {
                std::cout << "Response varbinds: " << resultVarbinds.size() << std::endl;
                for (size_t i = 0; i < resultVarbinds.size(); ++i) {
                    printVarbind(resultVarbinds[i], i);
                }
            }
        }
    });
    
    if (!success) {
        std::cerr << "ERROR: SET request failed" << std::endl;
    }
}

void printUsage(const char* progName) {
    std::cout << "Usage: " << progName << " <command> [options]" << std::endl;
    std::cout << "\nCommands:" << std::endl;
    std::cout << "  test <config.json>              - Test connectivity using config file" << std::endl;
    std::cout << "  connect <ip> <community>        - Test direct connection to controller" << std::endl;
    std::cout << "  get <ip> <community> <oid>      - Test GET for specific OID" << std::endl;
    std::cout << "  set <ip> <community> <oid> <type> <value> - Test SET for specific OID" << std::endl;
    std::cout << "    Types: 2=INTEGER, 4=OCTET_STR" << std::endl;
    std::cout << "  setmulti <ip> <community> <oid1> <type1> <value1> [oid2 type2 value2 ...] - Test SET with multiple varbinds" << std::endl;
    std::cout << "  walk <ip> <community> <oidPrefix> - Walk OID subtree using GETNEXT" << std::endl;
    std::cout << "  traps <port> <community>       - Test trap receiver (default port: 10162)" << std::endl;
    std::cout << "\nExamples:" << std::endl;
    std::cout << "  " << progName << " test config.json" << std::endl;
    std::cout << "  " << progName << " connect 192.168.4.77 UTMC" << std::endl;
    std::cout << "  " << progName << " get 192.168.4.77 UTMC 1.3.6.1.4.1.13267.3.2.4.1" << std::endl;
    std::cout << "  " << progName << " set 192.168.4.77 UTMC 1.3.6.1.4.1.13267.3.2.4.1 2 3" << std::endl;
    std::cout << "  " << progName << " setmulti 192.168.4.77 UTMC 1.3.6.1.4.1.13267.3.2.4.1 2 3 1.3.6.1.4.1.13267.3.2.4.2.1.20 2 1" << std::endl;
    std::cout << "  " << progName << " walk 192.168.4.77 UTMC 1.3.6.1.4.1.13267.3.2.4.2.1" << std::endl;
    std::cout << "  " << progName << " traps 10162 UTMC" << std::endl;
}

int main(int argc, char* argv[]) {
    signal(SIGINT, signalHandler);
    signal(SIGTERM, signalHandler);
    
    if (argc < 2) {
        printUsage(argv[0]);
        return 1;
    }
    
    std::string command = argv[1];
    
    if (command == "test") {
        if (argc < 3) {
            std::cerr << "Error: config file required" << std::endl;
            printUsage(argv[0]);
            return 1;
        }
        
        Config config;
        if (!ConfigLoader::load(argv[2], config)) {
            std::cerr << "Failed to load configuration" << std::endl;
            return 1;
        }
        
        std::cout << "Configuration loaded:" << std::endl;
        std::cout << "  Community: " << config.community << std::endl;
        std::cout << "  Objects: " << config.objects.size() << std::endl;
        
        SNMPHandler handler(config.community);
        
        for (const auto& obj : config.objects) {
            std::string addr = obj.addr.empty() ? obj.siteId : obj.addr;
            std::cout << "\n" << std::string(60, '=') << std::endl;
            std::cout << "Testing object: " << obj.strid << std::endl;
            std::cout << "ID: " << obj.id << ", Address: " << addr << std::endl;
            std::cout << std::string(60, '=') << std::endl;
            
            testBasicConnectivity(handler, addr, config.community);
            
            // Небольшая пауза между объектами
            std::this_thread::sleep_for(std::chrono::seconds(1));
        }
        
    } else if (command == "connect") {
        if (argc < 4) {
            std::cerr << "Error: IP address and community required" << std::endl;
            printUsage(argv[0]);
            return 1;
        }
        
        std::string address = argv[2];
        std::string community = argv[3];
        
        SNMPHandler handler(community);
        testBasicConnectivity(handler, address, community);
        
    } else if (command == "get") {
        if (argc < 5) {
            std::cerr << "Error: IP address, community and OID required" << std::endl;
            printUsage(argv[0]);
            return 1;
        }
        
        std::string address = argv[2];
        std::string community = argv[3];
        std::string oid = argv[4];
        
        SNMPHandler handler(community);
        testGetOID(handler, address, oid);
        
    } else if (command == "set") {
        if (argc < 6) {
            std::cerr << "Error: IP address, community, OID, type and value required" << std::endl;
            printUsage(argv[0]);
            return 1;
        }
        
        std::string address = argv[2];
        std::string community = argv[3];
        std::string oid = argv[4];
        int type = std::stoi(argv[5]);
        std::string value = argv[6];
        
        SNMPHandler handler(community);
        testSetOID(handler, address, oid, type, value);
        
    } else if (command == "setmulti") {
        if (argc < 6 || (argc - 4) % 3 != 0) {
            std::cerr << "Error: IP address, community, and at least one OID/type/value triplet required" << std::endl;
            std::cerr << "Usage: setmulti <ip> <community> <oid1> <type1> <value1> [oid2 type2 value2 ...]" << std::endl;
            printUsage(argv[0]);
            return 1;
        }
        
        std::string address = argv[2];
        std::string community = argv[3];
        
        std::vector<std::tuple<std::string, int, std::string>> varbindSpecs;
        for (int i = 4; i < argc; i += 3) {
            if (i + 2 >= argc) {
                std::cerr << "Error: Incomplete varbind specification" << std::endl;
                return 1;
            }
            std::string oid = argv[i];
            int type = std::stoi(argv[i + 1]);
            std::string value = argv[i + 2];
            varbindSpecs.push_back(std::make_tuple(oid, type, value));
        }
        
        SNMPHandler handler(community);
        testSetMultiple(handler, address, varbindSpecs);
        
    } else if (command == "walk") {
        if (argc < 5) {
            std::cerr << "Error: IP address, community and OID prefix required" << std::endl;
            printUsage(argv[0]);
            return 1;
        }
        std::string address = argv[2];
        std::string community = argv[3];
        std::string prefix = argv[4];
        SNMPHandler handler(community);
        testWalkOID(handler, address, community, prefix);

    } else if (command == "traps") {
        uint16_t port = 10162;
        std::string community = "UTMC";
        
        if (argc >= 3) {
            port = static_cast<uint16_t>(std::stoi(argv[2]));
        }
        if (argc >= 4) {
            community = argv[3];
        }
        
        SNMPHandler handler(community);
        testTrapReceiver(handler, port);
        
    } else {
        std::cerr << "Unknown command: " << command << std::endl;
        printUsage(argv[0]);
        return 1;
    }
    
    return 0;
}
