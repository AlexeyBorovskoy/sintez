#include "snmp_handler.h"
#include "config.h"
#include <iostream>
#include <iomanip>
#include <thread>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <signal.h>

extern "C" {
#include <net-snmp/library/asn1.h>
}

static bool running = true;

void signalHandler(int signal) {
    std::cout << "\nПолучен сигнал " << signal << ", завершаю работу..." << std::endl;
    running = false;
}

static bool parseIntValue(const std::string& input, int& out) {
    std::string num;
    bool started = false;
    for (char ch : input) {
        if (!started) {
            if (ch == '-' || std::isdigit(static_cast<unsigned char>(ch))) {
                num.push_back(ch);
                started = true;
            }
        } else if (std::isdigit(static_cast<unsigned char>(ch))) {
            num.push_back(ch);
        } else {
            break;
        }
    }
    if (num.empty() || num == "-") {
        return false;
    }
    try {
        out = std::stoi(num);
        return true;
    } catch (...) {
        return false;
    }
}

void printVarbind(const SNMPVarbind& vb, int index = -1) {
    std::cout << "  ";
    if (index >= 0) {
        std::cout << "[" << index << "] ";
    }
    std::cout << "OID: " << std::setw(50) << std::left << vb.oid;
    std::cout << " Тип: " << std::setw(15) << vb.type;
    std::cout << " Значение: " << vb.value << std::endl;
}

void testBasicConnectivity(SNMPHandler& handler, const std::string& address, const std::string& community) {
    std::cout << "\n=== Проверка базовой связности ===" << std::endl;
    std::cout << "Адрес: " << address << std::endl;
    std::cout << "SNMP community: " << community << std::endl;
    
    // Создание сессии
    std::cout << "\n1. Создание SNMP-сессии..." << std::endl;
    if (!handler.createSession(address, community)) {
        std::cerr << "ОШИБКА: не удалось создать SNMP-сессию" << std::endl;
        return;
    }
    std::cout << "   OK: сессия создана" << std::endl;
    
    // Тест 1: Получение системного времени работы (sysUpTime)
    std::cout << "\n2. Проверка GET: sysUpTime (1.3.6.1.2.1.1.3.0)..." << std::endl;
    std::vector<std::string> oids1 = {"1.3.6.1.2.1.1.3.0"};
    bool success1 = handler.get(address, oids1, [](bool error, const std::vector<SNMPVarbind>& varbinds) {
        if (error) {
            std::cerr << "   ОШИБКА: GET не выполнен (см. сообщения выше)" << std::endl;
        } else {
            std::cout << "   OK: получено varbind: " << varbinds.size() << std::endl;
            for (size_t i = 0; i < varbinds.size(); ++i) {
                printVarbind(varbinds[i], i);
            }
        }
    });
    
    if (!success1) {
        std::cerr << "   ОШИБКА: запрос GET не выполнен" << std::endl;
    }
    
    // Небольшая задержка между запросами
    std::this_thread::sleep_for(std::chrono::milliseconds(500));
    
    // Тест 2: Получение версии приложения
    std::cout << "\n3. Проверка GET: версия приложения (1.3.6.1.4.1.13267.3.2.1.2)..." << std::endl;
    std::vector<std::string> oids2 = {"1.3.6.1.4.1.13267.3.2.1.2"};
    bool success2 = handler.get(address, oids2, [](bool error, const std::vector<SNMPVarbind>& varbinds) {
        if (error) {
            std::cerr << "   ОШИБКА: GET не выполнен (см. сообщения выше)" << std::endl;
        } else {
            std::cout << "   OK: получено varbind: " << varbinds.size() << std::endl;
            for (size_t i = 0; i < varbinds.size(); ++i) {
                printVarbind(varbinds[i], i);
            }
        }
    });
    
    if (!success2) {
        std::cerr << "   ОШИБКА: запрос GET не выполнен" << std::endl;
    }
    
    std::this_thread::sleep_for(std::chrono::milliseconds(500));
    
    // Тест 3: Получение режима работы
    std::cout << "\n4. Проверка GET: operationMode (1.3.6.1.4.1.13267.3.2.4.1)..." << std::endl;
    // ВАЖНО: Этот контроллер требует OID БЕЗ .0 (в отличие от стандарта SNMP)
    std::vector<std::string> oids3 = {SNMPOID::UTC_TYPE2_OPERATION_MODE};
    bool success3 = handler.get(address, oids3, [](bool error, const std::vector<SNMPVarbind>& varbinds) {
        if (error) {
            std::cerr << "   ОШИБКА: GET не выполнен (см. сообщения выше)" << std::endl;
        } else {
            std::cout << "   OK: получено varbind: " << varbinds.size() << std::endl;
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
        std::cerr << "   ОШИБКА: запрос GET не выполнен" << std::endl;
    }
    
    std::this_thread::sleep_for(std::chrono::milliseconds(500));
    
    // Тест 4: Получение времени контроллера
    std::cout << "\n5. Проверка GET: время контроллера (1.3.6.1.4.1.13267.3.2.3.2)..." << std::endl;
    // ВАЖНО: Этот контроллер требует OID БЕЗ .0 (в отличие от стандарта SNMP)
    std::vector<std::string> oids4 = {"1.3.6.1.4.1.13267.3.2.3.2"};
    bool success4 = handler.get(address, oids4, [](bool error, const std::vector<SNMPVarbind>& varbinds) {
        if (error) {
            std::cerr << "   ОШИБКА: GET не выполнен (см. сообщения выше)" << std::endl;
        } else {
            std::cout << "   OK: получено varbind: " << varbinds.size() << std::endl;
            for (size_t i = 0; i < varbinds.size(); ++i) {
                printVarbind(varbinds[i], i);
            }
        }
    });
    
    if (!success4) {
        std::cerr << "   ОШИБКА: запрос GET не выполнен" << std::endl;
    }
    
    std::cout << "\n=== Basic Connectivity Test Complete ===" << std::endl;
}

void testTrapReceiver(SNMPHandler& handler, uint16_t port) {
    std::cout << "\n=== Тест приемника trap'ов ===" << std::endl;
    std::cout << "Listening on port " << port << "..." << std::endl;
    std::cout << "Нажмите Ctrl+C для остановки" << std::endl;
    
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
        std::cerr << "ОШИБКА: не удалось запустить приемник trap'ов" << std::endl;
        return;
    }
    
    std::cout << "Приемник trap'ов запущен. Ожидание..." << std::endl;
    
    int timeout = 30; // секунды
    int elapsed = 0;
    
    while (running && elapsed < timeout) {
        std::this_thread::sleep_for(std::chrono::seconds(1));
        elapsed++;
        if (elapsed % 5 == 0) {
            std::cout << "Ожидание... (" << elapsed << "/" << timeout << "с)" << std::endl;
        }
    }
    
    handler.stopReceiver();
    
    if (!received) {
        std::cout << "\nTrap'ы не получены за " << timeout << " секунд" << std::endl;
        std::cout << "Это нормально, если контроллер не настроен на отправку trap'ов" << std::endl;
    }
    
    std::cout << "\n=== Тест приемника trap'ов завершен ===" << std::endl;
}

void testWalkOID(SNMPHandler& handler, const std::string& address, const std::string& community, const std::string& oidPrefix) {
    std::cout << "\n=== Тест WALK: " << oidPrefix << " ===" << std::endl;
    std::cout << "ВНИМАНИЕ: будет выполнено много SNMP GET операций!" << std::endl;

    oid rootOid[MAX_OID_LEN];
    size_t rootLen = MAX_OID_LEN;
    if (!snmp_parse_oid(oidPrefix.c_str(), rootOid, &rootLen)) {
        std::cerr << "ОШИБКА: некорректный префикс OID" << std::endl;
        return;
    }

    // Initialize session
    if (!handler.createSession(address, community)) {
        std::cerr << "ОШИБКА: не удалось создать SNMP-сессию" << std::endl;
        return;
    }

    void* handle = handler.getSession(address);
    if (!handle) {
        std::cerr << "ОШИБКА: отсутствует handle SNMP-сессии" << std::endl;
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
            std::cerr << "ОШИБКА: не удалось создать PDU" << std::endl;
            break;
        }

        snmp_add_null_var(pdu, currentOid, currentLen);

        netsnmp_pdu* response = nullptr;
        int status = snmp_sess_synch_response(handle, pdu, &response);

        if (status != STAT_SUCCESS || response == nullptr) {
            std::cerr << "ОШИБКА: GETNEXT не выполнен (status=" << status << ")" << std::endl;
            if (response) snmp_free_pdu(response);
            break;
        }

        if (response->errstat != SNMP_ERR_NOERROR || response->variables == nullptr) {
            std::cerr << "ОШИБКА: ошибка ответа GETNEXT (errstat=" << response->errstat << ")" << std::endl;
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
    std::cout << "\n=== Тест GET: " << oid << " ===" << std::endl;
    
    std::vector<std::string> oids = {oid};
    bool success = handler.get(address, oids, [](bool error, const std::vector<SNMPVarbind>& varbinds) {
        if (error) {
            std::cerr << "ОШИБКА: GET не выполнен" << std::endl;
        } else {
            std::cout << "OK: получено varbind: " << varbinds.size() << std::endl;
            for (size_t i = 0; i < varbinds.size(); ++i) {
                printVarbind(varbinds[i], i);
            }
        }
    });
    
    if (!success) {
        std::cerr << "ОШИБКА: запрос GET не выполнен" << std::endl;
    }
}

void testSetOID(SNMPHandler& handler, const std::string& address, const std::string& oid, int type, const std::string& value) {
    std::cout << "\n=== Тест SET: " << oid << " ===" << std::endl;
    std::string typeName = (type == ASN_INTEGER) ? "INTEGER" : (type == ASN_OCTET_STR) ? "OCTET_STR" : "UNKNOWN";
    std::cout << "Тип: " << type << " (" << typeName << "), Значение: " << value << std::endl;
    std::cout << "ВНИМАНИЕ: команда изменит состояние контроллера!" << std::endl;
    
    SNMPVarbind varbind;
    varbind.oid = oid;
    varbind.type = type;
    varbind.value = value;
    
    std::vector<SNMPVarbind> varbinds = {varbind};
    bool success = handler.set(address, varbinds, [](bool error, const std::vector<SNMPVarbind>& resultVarbinds) {
        if (error) {
            std::cerr << "ОШИБКА: SET не выполнен" << std::endl;
        } else {
            std::cout << "OK: операция SET выполнена" << std::endl;
            if (!resultVarbinds.empty()) {
                std::cout << "Varbinds в ответе: " << resultVarbinds.size() << std::endl;
                for (size_t i = 0; i < resultVarbinds.size(); ++i) {
                    printVarbind(resultVarbinds[i], i);
                }
            }
        }
    });
    
    if (!success) {
        std::cerr << "ОШИБКА: запрос SET не выполнен" << std::endl;
    }
}

void testSetMultiple(SNMPHandler& handler, const std::string& address, const std::vector<std::tuple<std::string, int, std::string>>& varbindSpecs) {
    std::cout << "\n=== Тест SET (несколько varbind) ===" << std::endl;
    std::cout << "ВНИМАНИЕ: команда изменит состояние контроллера!" << std::endl;
    
    std::vector<SNMPVarbind> varbinds;
    for (const auto& spec : varbindSpecs) {
        SNMPVarbind varbind;
        varbind.oid = std::get<0>(spec);
        varbind.type = std::get<1>(spec);
        varbind.value = std::get<2>(spec);
        std::string typeName = (varbind.type == ASN_INTEGER) ? "INTEGER" : (varbind.type == ASN_OCTET_STR) ? "OCTET_STR" : "UNKNOWN";
        std::cout << "  OID: " << varbind.oid << ", Тип: " << varbind.type << " (" << typeName << "), Значение: " << varbind.value << std::endl;
        varbinds.push_back(varbind);
    }
    
    bool success = handler.set(address, varbinds, [](bool error, const std::vector<SNMPVarbind>& resultVarbinds) {
        if (error) {
            std::cerr << "ОШИБКА: SET не выполнен" << std::endl;
        } else {
            std::cout << "OK: операция SET выполнена" << std::endl;
            if (!resultVarbinds.empty()) {
                std::cout << "Varbinds в ответе: " << resultVarbinds.size() << std::endl;
                for (size_t i = 0; i < resultVarbinds.size(); ++i) {
                    printVarbind(resultVarbinds[i], i);
                }
            }
        }
    });
    
    if (!success) {
        std::cerr << "ОШИБКА: запрос SET не выполнен" << std::endl;
    }
}

// Высокоуровневый helper: SET_YF может быть принят SNMP, но не всегда реально включает ЖМ.
// Обертка делает подтверждение через utcReplyFR и поддерживает ретраи.
void testSetYFWithConfirm(SNMPHandler& handler, const std::string& address, int attempts, int timeoutSec) {
    std::cout << "\n=== Тест SET_YF (с подтверждением) ===" << std::endl;
    std::cout << "ВНИМАНИЕ: команда изменит состояние контроллера!" << std::endl;
    std::cout << "Адрес: " << address << std::endl;
    std::cout << "Попыток: " << attempts << ", confirmTimeout: " << timeoutSec << "с" << std::endl;

    if (attempts < 1) attempts = 1;
    if (timeoutSec < 1) timeoutSec = 1;

    for (int i = 1; i <= attempts; i++) {
        std::cout << "\nПопытка " << i << "/" << attempts << ": SNMP SET operationMode=3 + utcControlFF=1" << std::endl;

        std::vector<SNMPVarbind> varbinds = {
            {SNMPOID::UTC_TYPE2_OPERATION_MODE, ASN_INTEGER, "3"},
            {SNMPOID::UTC_CONTROL_FF, ASN_INTEGER, "1"},
        };

        bool setOk = handler.set(address, varbinds, [](bool error, const std::vector<SNMPVarbind>& resultVarbinds) {
            if (error) {
                std::cerr << "SET_YF: SET не выполнен" << std::endl;
            } else {
                std::cout << "SET_YF: SET принят (varbinds в ответе: " << resultVarbinds.size() << ")" << std::endl;
            }
        });

        if (!setOk) {
            std::cerr << "ОШИБКА: запрос SET не выполнен на транспортном уровне" << std::endl;
            return;
        }

        auto start = std::chrono::steady_clock::now();
        bool confirmed = false;
        while ((std::chrono::steady_clock::now() - start) < std::chrono::seconds(timeoutSec)) {
            int frValue = 0;
            bool getOk = handler.get(address, {SNMPOID::UTC_REPLY_FR}, [&](bool error, const std::vector<SNMPVarbind>& vbs) {
                if (error || vbs.empty()) {
                    return;
                }
                int v = 0;
                if (parseIntValue(vbs[0].value, v)) {
                    frValue = v;
                }
            });

            if (getOk && frValue != 0) {
                std::cout << "CONFIRMED: utcReplyFR=" << frValue << " (flashing)" << std::endl;
                confirmed = true;
                break;
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(200));
        }

        if (confirmed) {
            std::cout << "OK: ЖМ подтверждено" << std::endl;
            return;
        }

        std::cout << "WARN: Flashing not confirmed within timeout" << std::endl;
    }

    std::cerr << "ОШИБКА: SET_YF принят, но ЖМ не подтвердилось (utcReplyFR)" << std::endl;
}

static std::string shQuote(const std::string& s) {
    // Quote for /bin/sh -c using single quotes.
    std::string out;
    out.reserve(s.size() + 2);
    out.push_back('\'');
    for (char c : s) {
        if (c == '\'') {
            out.append("'\\''");
        } else {
            out.push_back(c);
        }
    }
    out.push_back('\'');
    return out;
}

static int runCmdCapture(const std::string& cmd, std::string& out) {
    out.clear();
    // Force stderr into stdout so we can show one combined trace on error.
    std::string full = cmd + " 2>&1";
    FILE* fp = popen(full.c_str(), "r");
    if (!fp) {
        out = "popen() failed";
        return 127;
    }
    char buf[4096];
    while (fgets(buf, sizeof(buf), fp)) {
        out.append(buf);
    }
    int rc = pclose(fp);
    if (WIFEXITED(rc)) {
        return WEXITSTATUS(rc);
    }
    return 128;
}

static bool sshRemote(const std::string& ip,
                      const std::string& user,
                      const std::string& pass,
                      const std::string& community,
                      const std::string& body,
                      std::string& out) {
    // We run controller-local SNMP via SSH:
    //   COMM=UTMC bash -lc '<body>'
    std::string remote = "COMM=" + community + " bash -lc " + shQuote(body);

    std::ostringstream cmd;
    cmd << "sshpass -p " << shQuote(pass) << " ssh"
        << " -o StrictHostKeyChecking=no"
        << " -o UserKnownHostsFile=/dev/null"
        << " -o LogLevel=ERROR"
        << " -o IdentitiesOnly=yes"
        << " -o PreferredAuthentications=password"
        << " -o PubkeyAuthentication=no"
        << " -o ConnectTimeout=5"
        << " " << user << "@" << ip
        << " " << shQuote(remote);

    int rc = runCmdCapture(cmd.str(), out);
    return rc == 0;
}

static bool sshRestoreNormal(const std::string& ip,
                             const std::string& user,
                             const std::string& pass,
                             const std::string& community,
                             std::string& out) {
    (void)community;
    // operationMode=1, LO=0, FF=0
    const std::string body =
        "set -euo pipefail\n"
        "snmpset -v1 -c \"$COMM\" -t 2 -r 1 -Oqv 127.0.0.1 "
        + SNMPOID::UTC_CONTROL_LO + " i 0 "
        + SNMPOID::UTC_CONTROL_FF + " i 0 "
        + SNMPOID::UTC_TYPE2_OPERATION_MODE + " i 1 >/dev/null\n"
        "sleep 1\n"
        "echo mode=$(snmpget -v1 -c \"$COMM\" -t 2 -r 1 -Oqv 127.0.0.1 " + SNMPOID::UTC_TYPE2_OPERATION_MODE + " 2>/dev/null || echo ?)"
        " fr=$(snmpget -v1 -c \"$COMM\" -t 2 -r 1 -Oqv 127.0.0.1 " + SNMPOID::UTC_REPLY_FR + " 2>/dev/null || echo ?)\n";

    return sshRemote(ip, user, pass, community, body, out);
}

static bool sshEnableYFUntilConfirm(const std::string& ip,
                                   const std::string& user,
                                   const std::string& pass,
                                   const std::string& community,
                                   int confirmTimeoutSec,
                                   int setPeriodSec,
                                   int& outFrValue,
                                   bool& outEnteredRemote,
                                   std::string& trace) {
    outFrValue = 0;
    trace.clear();
    outEnteredRemote = false;

    // Один раз перейти в UTC control.
    {
        std::string out;
        const std::string body =
            "set -euo pipefail\n"
            "snmpset -v1 -c \"$COMM\" -t 2 -r 1 -Oqv 127.0.0.1 " + SNMPOID::UTC_TYPE2_OPERATION_MODE + " i 3 >/dev/null\n"
            "echo mode_set_3\n";
        if (!sshRemote(ip, user, pass, community, body, out)) {
            trace += out;
            return false;
        }
        trace += out;
        outEnteredRemote = true;
    }

    if (confirmTimeoutSec < 1) confirmTimeoutSec = 1;
    if (setPeriodSec < 1) setPeriodSec = 1;

    auto start = std::chrono::steady_clock::now();
    while (running && (std::chrono::steady_clock::now() - start) < std::chrono::seconds(confirmTimeoutSec)) {
        std::string out;
        const std::string body =
            "set -euo pipefail\n"
            "snmpset -v1 -c \"$COMM\" -t 2 -r 1 -Oqv 127.0.0.1 " + SNMPOID::UTC_CONTROL_FF + " i 1 >/dev/null\n"
            "snmpget -v1 -c \"$COMM\" -t 2 -r 1 -Oqv 127.0.0.1 " + SNMPOID::UTC_REPLY_FR + " 2>/dev/null || echo ?\n";

        if (!sshRemote(ip, user, pass, community, body, out)) {
            trace += out;
            return false;
        }
        trace += out;

        int v = 0;
        if (parseIntValue(out, v) && v != 0) {
            outFrValue = v;
            return true;
        }

        std::this_thread::sleep_for(std::chrono::seconds(setPeriodSec));
    }

    if (!running) {
        trace += "interrupted by signal\n";
        return false;
    }
    trace += "timeout waiting for utcReplyFR != 0\n";
    return false;
}

static int testSshYellowFlashingFor(const std::string& ip,
                                   const std::string& community,
                                   int holdSec,
                                   const std::string& user,
                                   int confirmTimeoutSec,
                                   int keepPeriodSec,
                                   const std::string& passFileOpt) {
    std::string pass;
    if (!passFileOpt.empty()) {
        std::ifstream in(passFileOpt);
        if (!in) {
            std::cerr << "ОШИБКА: не удалось прочитать файл пароля: " << passFileOpt << "\n";
            return 2;
        }
        std::getline(in, pass);
    } else if (const char* passFileEnv = std::getenv("DK_PASS_FILE"); passFileEnv && *passFileEnv) {
        std::ifstream in(passFileEnv);
        if (!in) {
            std::cerr << "ОШИБКА: не удалось прочитать DK_PASS_FILE: " << passFileEnv << "\n";
            return 2;
        }
        std::getline(in, pass);
    } else if (const char* passEnv = std::getenv("DK_PASS"); passEnv && *passEnv) {
        pass = passEnv;
    }
    if (pass.empty()) {
        std::cerr << "ОШИБКА: для ssh_yf_for нужен SSH-пароль.\n";
        std::cerr << "Укажите один из вариантов:\n";
        std::cerr << "  - env DK_PASS=...\n";
        std::cerr << "  - env DK_PASS_FILE=/path/to/file\n";
        std::cerr << "  - опциональный последний аргумент <passFile>\n";
        std::cerr << "Цель: " << user << "@" << ip << "\n";
        return 2;
    }

    if (holdSec < 1) holdSec = 1;
    if (confirmTimeoutSec < 1) confirmTimeoutSec = 1;
    if (keepPeriodSec < 1) keepPeriodSec = 1;

    std::cout << "\n=== ssh_yf_for: ЖМ на " << holdSec << "с ===\n";
    std::cout << "Контроллер: " << ip << "\n";
    std::cout << "SNMP community: " << community << "\n";
    std::cout << "SSH пользователь: " << user << "\n";
    std::cout << "Таймаут подтверждения: " << confirmTimeoutSec << "с, период удержания: " << keepPeriodSec << "с\n";
    std::cout << "ВНИМАНИЕ: команда изменит состояние контроллера!\n";

    bool enteredRemote = false;
    bool restoreArmed = false;
    struct RestoreGuard {
        const std::string& ip;
        const std::string& user;
        const std::string& pass;
        const std::string& community;
        bool& armed;
        std::string out;
        ~RestoreGuard() {
            if (!armed) return;
            // Восстановление (по возможности); ошибки игнорируем.
            sshRestoreNormal(ip, user, pass, community, out);
        }
    } restoreGuard{ip, user, pass, community, restoreArmed};

    int fr = 0;
    std::string trace;
    if (!sshEnableYFUntilConfirm(ip, user, pass, community, confirmTimeoutSec, keepPeriodSec, fr, enteredRemote, trace)) {
        restoreArmed = enteredRemote;
        std::cerr << "ОШИБКА: не удалось включить/подтвердить ЖМ (utcReplyFR)\n";
        if (!trace.empty()) std::cerr << "Trace:\n" << trace << std::endl;
        return 3;
    }
    restoreArmed = true;

    std::cout << "ПОДТВЕРЖДЕНО: utcReplyFR=" << fr << "\n";
    std::cout << "Удержание " << holdSec << " секунд (переотправка utcControlFF=1 каждые " << keepPeriodSec << "с)\n";

    auto holdStart = std::chrono::steady_clock::now();
    while (running && (std::chrono::steady_clock::now() - holdStart) < std::chrono::seconds(holdSec)) {
        std::string out;
        const std::string body =
            "set -euo pipefail\n"
            "snmpset -v1 -c \"$COMM\" -t 2 -r 1 -Oqv 127.0.0.1 " + SNMPOID::UTC_CONTROL_FF + " i 1 >/dev/null\n"
            "echo ff_keep_1\n";
        if (!sshRemote(ip, user, pass, community, body, out)) {
            std::cerr << "ПРЕДУПРЕЖДЕНИЕ: не удалось переотправить keepalive (продолжаем)\n" << out << std::endl;
        }
        std::this_thread::sleep_for(std::chrono::seconds(keepPeriodSec));
    }

    if (!running) {
        std::cout << "Прервано: выполняю возврат в штатный режим\n";
    }
    std::cout << "Возврат в штатный режим (operationMode=1, LO=0, FF=0)\n";
    std::string out;
    if (!sshRestoreNormal(ip, user, pass, community, out)) {
        std::cerr << "ОШИБКА: не удалось вернуть штатный режим\n" << out << std::endl;
        return 4;
    }
    restoreArmed = false; // already restored
    std::cout << out;
    return 0;
}

void printUsage(const char* progName) {
    std::cout << "Использование: " << progName << " <команда> [опции]" << std::endl;
    std::cout << "\nКоманды:" << std::endl;
    std::cout << "  test <config.json>              - Проверка связности по конфигу" << std::endl;
    std::cout << "  connect <ip> <community>        - Проверка прямого подключения к контроллеру (SNMP)" << std::endl;
    std::cout << "  get <ip> <community> <oid>      - SNMP GET для конкретного OID" << std::endl;
    std::cout << "  set <ip> <community> <oid> <type> <value> - SNMP SET для конкретного OID" << std::endl;
    std::cout << "    Типы: 2=INTEGER, 4=OCTET_STR" << std::endl;
    std::cout << "  setmulti <ip> <community> <oid1> <type1> <value1> [oid2 type2 value2 ...] - SNMP SET с несколькими varbind" << std::endl;
    std::cout << "  set_yf <ip> <community> [attempts] [timeoutSec] - SET_YF с подтверждением через utcReplyFR" << std::endl;
    std::cout << "  ssh_yf_for <ip> <community> <seconds> [user] [confirmTimeoutSec] [keepPeriodSec] [passFile]" << std::endl;
    std::cout << "                               - Включить ЖМ на N секунд через SSH + локальный SNMP на контроллере." << std::endl;
    std::cout << "                                 Пароль: DK_PASS, DK_PASS_FILE или опциональный аргумент passFile." << std::endl;
    std::cout << "  walk <ip> <community> <oidPrefix> - WALK по поддереву OID (GETNEXT)" << std::endl;
    std::cout << "  traps <port> <community>       - Тест приемника trap'ов (порт по умолчанию: 10162)" << std::endl;
    std::cout << "\nПримеры:" << std::endl;
    std::cout << "  " << progName << " test config.json" << std::endl;
    std::cout << "  " << progName << " connect 192.168.4.77 UTMC" << std::endl;
    std::cout << "  " << progName << " get 192.168.4.77 UTMC 1.3.6.1.4.1.13267.3.2.4.1" << std::endl;
    std::cout << "  " << progName << " set 192.168.4.77 UTMC 1.3.6.1.4.1.13267.3.2.4.1 2 3" << std::endl;
    std::cout << "  " << progName << " setmulti 192.168.4.77 UTMC 1.3.6.1.4.1.13267.3.2.4.1 2 3 1.3.6.1.4.1.13267.3.2.4.2.1.20 2 1" << std::endl;
    std::cout << "  " << progName << " set_yf 192.168.4.77 UTMC 3 10" << std::endl;
    std::cout << "  DK_PASS=... " << progName << " ssh_yf_for 192.168.75.150 UTMC 30 voicelink 120 2" << std::endl;
    std::cout << "  " << progName << " ssh_yf_for 192.168.75.150 UTMC 30 voicelink 120 2 /tmp/dk_pass" << std::endl;
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
            std::cerr << "Ошибка: требуется файл конфигурации" << std::endl;
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
            std::cout << "Проверка объекта: " << obj.strid << std::endl;
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
        if (argc < 7) {
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
            std::cerr << "Использование: setmulti <ip> <community> <oid1> <type1> <value1> [oid2 type2 value2 ...]" << std::endl;
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

    } else if (command == "set_yf") {
        if (argc < 4) {
            std::cerr << "Error: IP address and community required" << std::endl;
            printUsage(argv[0]);
            return 1;
        }

        std::string address = argv[2];
        std::string community = argv[3];
        int attempts = (argc >= 5) ? std::stoi(argv[4]) : 3;
        int timeoutSec = (argc >= 6) ? std::stoi(argv[5]) : 10;

        SNMPHandler handler(community);
        testSetYFWithConfirm(handler, address, attempts, timeoutSec);

    } else if (command == "ssh_yf_for") {
        if (argc < 5) {
            std::cerr << "Error: IP address, community and duration seconds required" << std::endl;
            printUsage(argv[0]);
            return 1;
        }

        std::string ip = argv[2];
        std::string community = argv[3];
        int seconds = std::stoi(argv[4]);
        std::string user = (argc >= 6) ? argv[5] : "voicelink";
        int confirmTimeoutSec = (argc >= 7) ? std::stoi(argv[6]) : 120;
        int keepPeriodSec = (argc >= 8) ? std::stoi(argv[7]) : 2;
        std::string passFile = (argc >= 9) ? argv[8] : "";

        return testSshYellowFlashingFor(ip, community, seconds, user, confirmTimeoutSec, keepPeriodSec, passFile);
        
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
