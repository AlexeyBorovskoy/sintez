#include "object_manager.h"
#include <iostream>
#include <sstream>
#include <ctime>
#include <algorithm>
#include <cstdint>
#include <chrono>
#include <thread>
#include <cctype>
#include <set>
extern "C" {
#include <net-snmp/library/asn1.h>
}

namespace {
bool parseIntValue(const std::string& input, int& out) {
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

bool parseFirstHexByte(const std::string& input, uint8_t& out) {
    char first = 0;
    char second = 0;
    bool gotFirst = false;
    for (char ch : input) {
        if (std::isxdigit(static_cast<unsigned char>(ch))) {
            if (!gotFirst) {
                first = ch;
                gotFirst = true;
            } else {
                second = ch;
                std::string byteStr;
                byteStr.push_back(first);
                byteStr.push_back(second);
                try {
                    out = static_cast<uint8_t>(std::stoi(byteStr, nullptr, 16));
                    return true;
                } catch (...) {
                    return false;
                }
            }
        } else if (gotFirst) {
            gotFirst = false;
        }
    }
    return false;
}
} // namespace

SpectrObject::SpectrObject(const ObjectConfig& config,
                           const std::string& community,
                           const YFConfig& yfConfig,
                           SNMPHandler* snmpHandler,
                           TcpClient* tcpClient)
    : config_(config), community_(community), yfConfig_(yfConfig), snmpHandler_(snmpHandler), tcpClient_(tcpClient),
      eventCounter_(0), eventMask_(1), stageStartTime_(0), cycleStartTime_(0),
      yfHoldActive_(false), yfStop_(false), savedOperationMode_(3) {  // По умолчанию remote (3)
    
    // Создание SNMP сессии для этого объекта
    if (snmpHandler_) {
        snmpHandler_->createSession(config.addr, community_);
    }
}

SpectrObject::~SpectrObject() {
    // Останавливаем наш фоновой поток, но не посылаем никаких "команд остановки"
    // контроллеру при завершении процесса.
    stopYFHold();
}

void SpectrObject::processNotification(const SNMPNotification& notification) {
    std::cout << "Inform from " << notification.sourceAddress << std::endl;
    
    std::map<std::string, uint8_t> stateChanges;
    bool hasTakt = false;
    bool hasStage = false;
    bool hasRegime = false;
    bool hasControlSource = false;
    
    uint8_t takt = 0;
    uint8_t stage = 0;
    uint8_t regime = 0;
    uint8_t controlSource = 0;
    
    for (const auto& varbind : notification.varbinds) {
        processSNMPVarbind(varbind);
        
        // Обработка специфичных OID
        if (varbind.oid == SNMPOID::UTC_REPLY_GN_1) {
            // Takt
            int value = 0;
            if (parseIntValue(varbind.value, value)) {
                takt = static_cast<uint8_t>(value);
                hasTakt = true;
            }
        } else if (varbind.oid == SNMPOID::UTC_REPLY_GN) {
            // Stage
            int value = 0;
            if (parseIntValue(varbind.value, value)) {
                stage = static_cast<uint8_t>(value);
                hasStage = true;
            }
        } else if (varbind.oid == SNMPOID::UTC_REPLY_FR) {
            // Regime (Flashing Amber)
            int value = 0;
            if (parseIntValue(varbind.value, value)) {
                if (value != 0) {
                    regime = 2;
                    hasRegime = true;
                }
            }
        } else if (varbind.oid == SNMPOID::UTC_REPLY_REGIME_OFF) {
            // Regime reset (as in Node)
            int value = 0;
            if (parseIntValue(varbind.value, value) && value != 0) {
                regime = 0;
                hasRegime = true;
            }
        } else if (varbind.oid == SNMPOID::UTC_TYPE2_OPERATION_MODE) {
            // Control Source
            int value = 0;
            if (parseIntValue(varbind.value, value)) {
                controlSource = (value == 3) ? 3 : 1;
                hasControlSource = true;
            }
        }
    }
    
    // Формирование изменений состояния
    if (hasTakt) {
        stateChanges["stage"] = takt;
        if (hasStage) {
            stateChanges["transition"] = (stage == takt) ? 0 : 255;
        }
    } else if (hasStage && stage > 48) {
        stateChanges["stage"] = stage - 48;
        stateChanges["transition"] = 0;
    }
    
    if (hasStage && stateChanges.find("stage") != stateChanges.end()) {
        stateChanges["stageLen"] = 255;
        stateChanges["algorithm"] = 1;
        // keyRegime: 0=OS (normal). For UTMC we infer normal regime when stage info is present.
        stateChanges["regime"] = 0;
    }
    
    if (hasRegime) {
        stateChanges["regime"] = regime;
    }
    
    if (hasControlSource) {
        stateChanges["controlSource"] = controlSource;
    }
    
    if (!stateChanges.empty()) {
        changeState(stateChanges);
        
        // Если controlSource неизвестен, запросить его
        if (state_.controlSource == 255) {
            requestOperationMode();
        }
    }
}

void SpectrObject::processSNMPVarbind(const SNMPVarbind& varbind) {
    // Игнорируем некоторые OID
    if (varbind.oid == SNMPOID::UTC_REPLY_ENTRY + ".14" ||
        varbind.oid == SNMPOID::UTC_REPLY_ENTRY + ".15" ||
        varbind.oid == SNMPOID::UTC_REPLY_BY_EXCEPTION ||
        varbind.oid == SNMPOID::UTC_CONTROL_FN ||
        varbind.oid == SNMPOID::UTC_CONTROL_LO ||
        varbind.oid == SNMPOID::UTC_CONTROL_FF ||
        varbind.oid == SNMPOID::UTC_REPLY_GN ||
        varbind.oid == SNMPOID::UTC_REPLY_GN_1 ||
        varbind.oid == SNMPOID::UTC_REPLY_FR ||
        varbind.oid == SNMPOID::UTC_REPLY_REGIME_OFF ||
        varbind.oid == SNMPOID::UTC_TYPE2_OPERATION_MODE ||
        varbind.oid == SNMPOID::SYS_UP_TIME ||
        varbind.oid == SNMPOID::SNMP_TRAP_OID) {
        return;
    }
    
    // Логирование неизвестных OID
    std::cout << "  ? " << varbind.oid << " " << varbind.type << " " << varbind.value << std::endl;
}

void SpectrObject::processCommand(const SpectrProtocol::ParsedCommand& command) {
    if (!command.isValid) {
        sendToITS(SpectrProtocol::formatResult(command.error, command.requestId));
        return;
    }
    
    SpectrError result = SpectrError::UNINDENT; // Unknown command by default

    auto isKnownButUnsupported = [](const std::string& cmd) -> bool {
        // Keep in sync with command list used by ASUDD (Spectr protocol).
        // We reply NOT_EXEC_4 instead of UNINDENT so the upstream sees "known command but not possible".
        static const std::set<std::string> k = {
            // SET_ (unsupported)
            "SET_TOUT", "SET_PROG", "SET_GROUP", "SET_DATE", "SET_TIME", "SET_TDTIME",
            "SET_VERB", "SET_DPROG", "SET_DDMAP", "SET_DSDY", "SET_CONFIG", "SET_VPU",
            "SET_EVTCFG", "SET_QUERY", "SET_PASSKY", "SET_STRAT", "SET_ASTATE", "SET_APSTATE",
            "SET_DEFAULT", "SET_ADEFAULT",
            // GET_ (unsupported)
            "GET_GROUP", "GET_SENS", "GET_SWITCH", "GET_TWP", "GET_TDET", "GET_JRNL",
            "GET_POWER", "GET_VPU", "GET_QUERY", "GET_PASSDB", "GET_PASSKY", "GET_STATE",
            "GET_DPROG", "GET_CONFIG_HASH", "GET_CONFIG_SIZE",
        };
        return k.find(cmd) != k.end();
    };
    
    if (command.command == "SET_PHASE") {
        if (!command.params.empty()) {
            try {
                uint8_t phase = static_cast<uint8_t>(std::stoi(command.params[0]));
                result = setPhase(command.requestId, phase);
            } catch (...) {
                result = SpectrError::BAD_PARAM;
            }
        } else {
            result = SpectrError::BAD_PARAM;
        }
    } else if (command.command == "SET_YF") {
        result = setYF(command.requestId);
    } else if (command.command == "SET_OS") {
        result = setOS(command.requestId);
    } else if (command.command == "SET_LOCAL") {
        result = setLocal(command.requestId);
    } else if (command.command == "SET_START") {
        result = setStart(command.requestId);
    } else if (command.command == "GET_STAT") {
        std::string response = getStat(command.requestId);
        sendToITS(response);
        return;
    } else if (command.command == "GET_REFER") {
        std::string response = getRefer(command.requestId);
        sendToITS(response);
        return;
    } else if (command.command == "GET_CONFIG") {
        if (command.params.size() >= 2) {
            try {
                uint32_t param1 = std::stoul(command.params[0]);
                try {
                    uint32_t param2 = std::stoul(command.params[1]);
                    std::string response = getConfig(command.requestId, param1, param2);
                    sendToITS(response);
                    return;
                } catch (...) {
                    result = (param1 != 0) ? SpectrError::NOT_EXEC_2 : SpectrError::BAD_PARAM;
                }
            } catch (...) {
                result = SpectrError::BAD_PARAM;
            }
        } else {
            result = SpectrError::BAD_PARAM;
        }
    } else if (command.command == "GET_DATE") {
        std::string response = getDate(command.requestId);
        sendToITS(response);
        return;
    } else if (command.command == "SET_EVENT") {
        if (!command.params.empty()) {
            try {
                uint16_t mask = static_cast<uint16_t>(std::stoi(command.params[0]));
                if (mask >= 0 && mask <= 65535) {
                    eventMask_ = mask | 1;
                    result = SpectrError::OK;
                } else {
                    result = SpectrError::BAD_PARAM;
                }
            } catch (...) {
                result = SpectrError::BAD_PARAM;
            }
        } else {
            result = SpectrError::BAD_PARAM;
        }
    } else if (isKnownButUnsupported(command.command)) {
        result = SpectrError::NOT_EXEC_4;
    }
    
    if (command.command == "SET_PHASE" ||
        command.command == "SET_YF" ||
        command.command == "SET_OS" ||
        command.command == "SET_LOCAL" ||
        command.command == "SET_START") {
        if (result != SpectrError::OK) {
            sendToITS(SpectrProtocol::formatResult(result, command.requestId));
        }
        return;
    }

    sendToITS(SpectrProtocol::formatResult(result, command.requestId));
}

void SpectrObject::sendEvent(uint8_t eventType, const std::vector<std::string>& params) {
    uint16_t counter = ++eventCounter_;
    counter &= 0xFFFF;
    
    std::string event = SpectrProtocol::formatEvent(counter, eventType, params);
    sendToITS(event);
}

void SpectrObject::updateState() {
    auto now = std::chrono::system_clock::now();
    auto nowMs = std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()).count();
    
    if (stageStartTime_ > 0) {
        state_.stageCounter = static_cast<uint16_t>((nowMs - stageStartTime_) / 1000);
    } else {
        state_.stageCounter = 0;
    }
    
    if (cycleStartTime_ > 0) {
        state_.cicleCounter = static_cast<uint16_t>((nowMs - cycleStartTime_) / 1000);
    } else {
        state_.cicleCounter = 0;
    }
}

void SpectrObject::changeState(const std::map<std::string, uint8_t>& changes) {
    bool controlSourceChanged = false;
    bool stageChanged = false;
    
    std::vector<std::string> controlSourceFields = {"controlSource", "algorithm", "plan", "regime"};
    std::vector<std::string> stageFields = {"stage", "stageLen", "transition"};
    
    for (const auto& change : changes) {
        if (change.first == "stage" && state_.stage != change.second) {
            auto now = std::chrono::system_clock::now();
            stageStartTime_ = std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()).count();
            if (change.second == 1) {
                cycleStartTime_ = stageStartTime_;
            }
        }
        
        // Обновление состояния
        if (change.first == "controlSource") state_.controlSource = change.second;
        else if (change.first == "algorithm") state_.algorithm = change.second;
        else if (change.first == "plan") state_.plan = change.second;
        else if (change.first == "regime") state_.regime = change.second;
        else if (change.first == "stage") state_.stage = change.second;
        else if (change.first == "stageLen") state_.stageLen = change.second;
        else if (change.first == "transition") state_.transition = change.second;
        
        if (std::find(controlSourceFields.begin(), controlSourceFields.end(), change.first) != controlSourceFields.end()) {
            controlSourceChanged = true;
        }
        if (std::find(stageFields.begin(), stageFields.end(), change.first) != stageFields.end()) {
            stageChanged = true;
        }
    }
    
    // Отправка событий
    if ((eventMask_ & 0x10) && stageChanged) {
        std::vector<std::string> params = {
            std::to_string(state_.stage),
            std::to_string(state_.stageLen),
            std::to_string(state_.transition)
        };
        sendEvent(4, params);
    }
    
    if ((eventMask_ & 0x08) && controlSourceChanged) {
        std::vector<std::string> params = {
            "1",
            std::to_string(state_.controlSource),
            std::to_string(state_.algorithm),
            std::to_string(state_.plan),
            std::to_string(state_.regime)
        };
        sendEvent(3, params);
    }
}

SpectrError SpectrObject::setPhase(const std::string& requestId, uint8_t phase) {
    // Any manual control command should stop YF keepalive.
    stopYFHold();

    if (phase < 1 || phase > 7) {
        return SpectrError::BAD_PARAM;
    }
    
    if (!snmpHandler_) {
        return SpectrError::NOT_EXEC_5; // Internal error
    }
    
    std::vector<SNMPVarbind> varbinds;
    
    // Установка режима работы в удаленный (3)
    SNMPVarbind modeVarbind;
    modeVarbind.oid = SNMPOID::UTC_TYPE2_OPERATION_MODE;
    modeVarbind.type = ASN_INTEGER;
    modeVarbind.value = "3";
    varbinds.push_back(modeVarbind);
    
    // Установка фазы через Force Bits (utcControlFn)
    // ИСПРАВЛЕНО: В работающем коде SCN не используется в OID
    SNMPVarbind phaseVarbind;
    phaseVarbind.oid = SNMPOID::UTC_CONTROL_FN;
    phaseVarbind.type = ASN_OCTET_STR;
    // Bit mask: 1 << (phase - 1)
    uint8_t bitMask = 1 << (phase - 1);
    phaseVarbind.value = std::string(1, static_cast<char>(bitMask));
    varbinds.push_back(phaseVarbind);
    
    bool submitted = snmpHandler_->set(config_.addr, varbinds, [this, requestId](bool error, const std::vector<SNMPVarbind>&) {
        if (error) {
            std::cerr << "SET_PHASE failed for " << config_.addr << std::endl;
        }
        SpectrError result = error ? SpectrError::NOT_EXEC_5 : SpectrError::OK;
        sendToITS(SpectrProtocol::formatResult(result, requestId));
    });
    
    return submitted ? SpectrError::OK : SpectrError::NOT_EXEC_5;
}

SpectrError SpectrObject::setYF(const std::string& requestId) {
    if (!snmpHandler_) {
        return SpectrError::NOT_EXEC_5;
    }
    
    // Важно: SNMP SET может пройти, но физическое ЖМ включается не всегда сразу.
    // Поэтому делаем 1 SET + запускаем фонового "страховщика" (yfHoldThread),
    // который в течение короткого окна повторит SET_YF в "удобный момент" и
    // подтвердит включение по utcReplyFR. В ответ на команду ITS возвращаемся сразу.

    std::vector<SNMPVarbind> varbinds;

    SNMPVarbind modeVarbind;
    modeVarbind.oid = SNMPOID::UTC_TYPE2_OPERATION_MODE;
    modeVarbind.type = ASN_INTEGER;
    modeVarbind.value = "3";
    varbinds.push_back(modeVarbind);

    SNMPVarbind ffVarbind;
    ffVarbind.oid = SNMPOID::UTC_CONTROL_FF;
    ffVarbind.type = ASN_INTEGER;
    ffVarbind.value = "1";
    varbinds.push_back(ffVarbind);

    bool submitted = snmpHandler_->set(config_.addr, varbinds, [this, requestId](bool error, const std::vector<SNMPVarbind>&) {
        SpectrError result = error ? SpectrError::NOT_EXEC_5 : SpectrError::OK;
        sendToITS(SpectrProtocol::formatResult(result, requestId));

        if (!error) {
            // Не блокируем основной поток обработки команд.
            startYFHold();
        }
    });

    return submitted ? SpectrError::OK : SpectrError::NOT_EXEC_5;
}

SpectrError SpectrObject::setOS(const std::string& requestId) {
    if (!snmpHandler_) {
        return SpectrError::NOT_EXEC_5;
    }

    // Turning outputs off must stop YF keepalive.
    stopYFHold();
    
    std::vector<SNMPVarbind> varbinds;
    
    SNMPVarbind modeVarbind;
    modeVarbind.oid = SNMPOID::UTC_TYPE2_OPERATION_MODE;
    modeVarbind.type = ASN_INTEGER;
    modeVarbind.value = "3";
    varbinds.push_back(modeVarbind);
    
    // SetOFF (все выключено)
    // ИСПРАВЛЕНО: В работающем коде SCN не используется в OID
    SNMPVarbind loVarbind;
    loVarbind.oid = SNMPOID::UTC_CONTROL_LO;
    loVarbind.type = ASN_INTEGER;
    loVarbind.value = "1";
    varbinds.push_back(loVarbind);
    
    bool submitted = snmpHandler_->set(config_.addr, varbinds, [this, requestId](bool error, const std::vector<SNMPVarbind>&) {
        SpectrError result = error ? SpectrError::NOT_EXEC_5 : SpectrError::OK;
        sendToITS(SpectrProtocol::formatResult(result, requestId));
    });
    
    return submitted ? SpectrError::OK : SpectrError::NOT_EXEC_5;
}

SpectrError SpectrObject::setLocal(const std::string& requestId) {
    if (!snmpHandler_) {
        return SpectrError::NOT_EXEC_5;
    }

    // Leaving remote control must stop YF keepalive.
    stopYFHold();
    
    std::vector<SNMPVarbind> varbinds;
    
    // SetOFF и SetAF
    // ИСПРАВЛЕНО: В работающем коде SCN не используется в OID
    SNMPVarbind loVarbind;
    loVarbind.oid = SNMPOID::UTC_CONTROL_LO;
    loVarbind.type = ASN_INTEGER;
    loVarbind.value = "0";
    varbinds.push_back(loVarbind);
    
    SNMPVarbind ffVarbind;
    ffVarbind.oid = SNMPOID::UTC_CONTROL_FF;
    ffVarbind.type = ASN_INTEGER;
    ffVarbind.value = "0";
    varbinds.push_back(ffVarbind);
    
    SNMPVarbind modeVarbind;
    modeVarbind.oid = SNMPOID::UTC_TYPE2_OPERATION_MODE;
    modeVarbind.type = ASN_INTEGER;
    modeVarbind.value = "1";
    varbinds.push_back(modeVarbind);
    
    bool submitted = snmpHandler_->set(config_.addr, varbinds, [this, requestId](bool error, const std::vector<SNMPVarbind>&) {
        SpectrError result = error ? SpectrError::NOT_EXEC_5 : SpectrError::OK;
        sendToITS(SpectrProtocol::formatResult(result, requestId));
    });
    
    return submitted ? SpectrError::OK : SpectrError::NOT_EXEC_5;
}

SpectrError SpectrObject::setStart(const std::string& requestId) {
    if (!snmpHandler_) {
        return SpectrError::NOT_EXEC_5;
    }

    // Restart/other actions must stop YF keepalive.
    stopYFHold();
    
    std::vector<SNMPVarbind> varbinds;
    
    // SetStart использует UTC_CONTROL_FN.5
    // ИСПРАВЛЕНО: В работающем коде SCN не используется в OID
    std::string startOID = SNMPOID::UTC_CONTROL_FN + ".5";
    SNMPVarbind startVarbind;
    startVarbind.oid = startOID;
    startVarbind.type = ASN_INTEGER;
    startVarbind.value = "1";
    varbinds.push_back(startVarbind);
    
    SNMPVarbind modeVarbind;
    modeVarbind.oid = SNMPOID::UTC_TYPE2_OPERATION_MODE;
    modeVarbind.type = ASN_INTEGER;
    modeVarbind.value = "1";
    varbinds.push_back(modeVarbind);
    
    bool submitted = snmpHandler_->set(config_.addr, varbinds, [this, requestId](bool error, const std::vector<SNMPVarbind>&) {
        SpectrError result = error ? SpectrError::NOT_EXEC_5 : SpectrError::OK;
        sendToITS(SpectrProtocol::formatResult(result, requestId));
    });
    
    return submitted ? SpectrError::OK : SpectrError::NOT_EXEC_5;
}

std::string SpectrObject::getStat(const std::string& requestId) {
    // Обновление состояния с контроллера (по возможности), чтобы не полагаться только на trap'ы.
    if (snmpHandler_) {
        snmpHandler_->get(config_.addr,
                          {SNMPOID::UTC_REPLY_GN, SNMPOID::UTC_REPLY_FR, SNMPOID::UTC_TYPE2_OPERATION_MODE},
                          [&](bool error, const std::vector<SNMPVarbind>& vbs) {
                              if (error || vbs.size() < 3) return;

                              // Стадия по GN-битмаске (первый hex-байт)
                              uint8_t stage = 255;
                              uint8_t byte = 0;
                              if (parseFirstHexByte(vbs[0].value, byte)) {
                                  for (int i = 0; i < 8; i++) {
                                      if (byte & (1 << i)) {
                                          stage = static_cast<uint8_t>(i + 1);
                                          break;
                                      }
                                  }
                              }
                              if (stage != 255) {
                                  state_.stage = stage;
                                  state_.stageLen = 255;
                                  state_.transition = 0;
                                  if (state_.regime != 2) {
                                      state_.algorithm = 1;
                                  }
                              }

                              // Режим ЖМ по FR
                              int fr = 0;
                              if (parseIntValue(vbs[1].value, fr) && fr != 0) {
                                  state_.regime = 2;   // keyRegime=ЖМ
                                  state_.algorithm = 0; // controlAlgorithm=ЖМ
                              } else if (state_.regime == 2) {
                                  // If FR dropped, return to unknown/normal regime
                                  state_.regime = 0;
                                  if (state_.algorithm == 0) state_.algorithm = 1;
                              }

                              // controlSource from operationMode: 3=ASUDD(remote), otherwise local
                              int mode = 0;
                              if (parseIntValue(vbs[2].value, mode)) {
                                  state_.controlSource = (mode == 3) ? 3 : 1;
                              }
                          });
    }

    updateState();
    
    std::stringstream ss;
    ss << "STAT " << static_cast<int>(state_.damage) << " "
       << static_cast<int>(state_.error) << " "
       << static_cast<int>(state_.unitsGood) << " "
       << static_cast<int>(state_.units) << " "
       << static_cast<int>(state_.powerFlags) << " "
       << static_cast<int>(state_.controlSource) << " "
       << static_cast<int>(state_.algorithm) << " "
       << static_cast<int>(state_.plan) << " "
       << state_.cicleCounter << " "
       << static_cast<int>(state_.stage) << " "
       << static_cast<int>(state_.stageLen) << " "
       << state_.stageCounter << " "
       << static_cast<int>(state_.transition) << " "
       << static_cast<int>(state_.regime) << " "
       << static_cast<int>(state_.testMode) << " "
       << static_cast<int>(state_.syncError) << " "
       << static_cast<int>(state_.dynamicFlags);
    
    return SpectrProtocol::formatResult(SpectrError::OK, requestId, ss.str());
}

std::string SpectrObject::getRefer(const std::string& requestId) {
    std::stringstream ss;
    ss << "\"Spectr\" " << config_.id << " \"" << config_.strid << "\"";
    return SpectrProtocol::formatResult(SpectrError::OK, requestId, ss.str());
}

std::string SpectrObject::getConfig(const std::string& requestId, uint32_t param1, uint32_t param2) {
    std::string configText;
    if (param1 == 0 && param2 == 0) {
        configText = "#TxtCfg Spectr:" + config_.strid + " ";
    } else {
        configText = "BEGIN:\nEND.\n";
    }
    
    std::string hexConfig = SpectrProtocol::toHex(configText);
    std::stringstream ss;
    ss << "0 0 [" << hexConfig << "]";
    return SpectrProtocol::formatResult(SpectrError::OK, requestId, ss.str());
}

std::string SpectrObject::getDate(const std::string& requestId) {
    std::time_t now = std::time(nullptr);
    std::tm* local = std::localtime(&now);
    
    std::stringstream ss;
    ss << local->tm_mday << "/" << local->tm_mon << "/" << (1900 + local->tm_year);
    return SpectrProtocol::formatResult(SpectrError::OK, requestId, ss.str());
}

void SpectrObject::sendToITS(const std::string& data) {
    std::cout << config_.id << " <- " << data;
    if (tcpClient_) {
        tcpClient_->send(data);
    }
}

std::string SpectrObject::buildOIDWithSCN(const std::string& baseOID) {
    // Формирование OID с SCN для табличных объектов
    // Формат: BASE_OID.timestamp.SCN_ASCII_CODES
    // timestamp = 1 означает "NOW" (немедленное выполнение)
    
    if (config_.siteId.empty()) {
        // Если SCN не задан, возвращаем базовый OID (для обратной совместимости)
        return baseOID;
    }
    
    std::string oid = baseOID + ".1";  // timestamp = 1 (NOW)
    
    // Добавляем ASCII коды символов SCN
    for (char c : config_.siteId) {
        oid += "." + std::to_string(static_cast<unsigned char>(c));
    }
    
    return oid;
}

void SpectrObject::requestOperationMode() {
    if (!snmpHandler_) {
        return;
    }
    
    // ВАЖНО: Этот контроллер требует OID БЕЗ .0 (в отличие от стандарта SNMP)
    // Node.js библиотека автоматически добавляет .0, но контроллер работает без него
    std::vector<std::string> oids = {SNMPOID::UTC_TYPE2_OPERATION_MODE};
    
    snmpHandler_->get(config_.addr, oids, [this](bool error, const std::vector<SNMPVarbind>& varbinds) {
        if (!error && !varbinds.empty()) {
            int value = 0;
            if (parseIntValue(varbinds[0].value, value)) {
                uint8_t controlSource = (value == 3) ? 3 : 1;
                changeState({{"controlSource", controlSource}});
            } else {
                std::cerr << "Failed to parse operation mode" << std::endl;
            }
        }
    });
}

SpectrObject::PhaseInfo SpectrObject::getCurrentPhaseInfo() {
    PhaseInfo info;
    
    if (!snmpHandler_) {
        return info;
    }
    
    // Получение текущей фазы (Gn), длительности фазы и счётчика
    std::vector<std::string> oids = {
        SNMPOID::UTC_REPLY_GN,
        SNMPOID::UTC_REPLY_STAGE_LENGTH,
        SNMPOID::UTC_REPLY_STAGE_COUNTER
    };
    
    bool completed = false;
    PhaseInfo result;
    
    snmpHandler_->get(config_.addr, oids, [&result, &completed](bool error, const std::vector<SNMPVarbind>& varbinds) {
        if (error || varbinds.size() < 3) {
            completed = true;
            return;
        }
        
        try {
            // Парсинг текущей фазы (Gn) - битовая маска
            const std::string& phaseHex = varbinds[0].value;
            if (!phaseHex.empty()) {
                uint8_t phaseValue = 0;
                if (parseFirstHexByte(phaseHex, phaseValue)) {
                    // Определение номера фазы из битовой маски
                    for (int i = 0; i < 8; i++) {
                        if (phaseValue & (1 << i)) {
                            result.phase = i + 1;
                            break;
                        }
                    }
                }
            }
            
            // Парсинг длительности фазы
            if (!varbinds[1].value.empty()) {
                int value = 0;
                if (parseIntValue(varbinds[1].value, value)) {
                    result.stageLength = static_cast<uint16_t>(value);
                }
            }
            
            // Парсинг счётчика фазы
            if (!varbinds[2].value.empty()) {
                int value = 0;
                if (parseIntValue(varbinds[2].value, value)) {
                    result.stageCounter = static_cast<uint16_t>(value);
                }
            }
            
            result.isValid = (result.phase > 0 && result.phase <= 7);
        } catch (...) {
            // Ошибка парсинга
        }
        
        completed = true;
    });
    
    // Ожидание завершения (с таймаутом)
    auto startWait = std::chrono::steady_clock::now();
    while (!completed && 
           (std::chrono::steady_clock::now() - startWait) < std::chrono::seconds(3)) {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
    
    return result;
}

bool SpectrObject::isSpecialPhase(uint8_t phase) {
    // Специальные фазы (nominated stages) согласно конфигурации контроллера: 1, 2, 3, 4
    return (phase >= 1 && phase <= 4);
}

void SpectrObject::startYFHold() {
    if (yfHoldActive_) {
        return; // Уже активно
    }
    
    yfHoldActive_ = true;
    yfStop_ = false;
    
    std::cout << "[YF_HOLD] Start: object=" << config_.id
              << ", confirmTimeoutSec=" << yfConfig_.confirmTimeoutSec
              << ", keepPeriodMs=" << yfConfig_.keepPeriodMs
              << ", maxHoldSec=" << yfConfig_.maxHoldSec << std::endl;
    
    // Запуск фонового потока удержания
    yfHoldThread_ = std::thread(&SpectrObject::yfHoldThread, this);
}

void SpectrObject::stopYFHold() {
    if (!yfHoldActive_) {
        return;
    }
    
    std::cout << "[YF_HOLD] Stop requested" << std::endl;
    yfStop_ = true;
    
    if (yfHoldThread_.joinable()) {
        yfHoldThread_.join();
    }
    
    yfHoldActive_ = false;

    std::cout << "[YF_HOLD] Stopped" << std::endl;
}

void SpectrObject::yfHoldThread() {
    // Поток keepalive для ЖМ (жёлтое мигание).
    // Controller behavior observed: require periodic reassert utcControlFF=1.
    // We:
    //  - switch to operationMode=3 once,
    //  - reassert FF=1 periodically,
    //  - confirm by utcReplyFR (!=0) within confirmTimeoutSec (best-effort),
    //  - keep reasserting until stopYFHold() or maxHoldSec (if >0).

    const int confirmTimeoutSec = (yfConfig_.confirmTimeoutSec > 0) ? yfConfig_.confirmTimeoutSec : 120;
    const auto sendInterval = std::chrono::milliseconds((yfConfig_.keepPeriodMs > 0) ? yfConfig_.keepPeriodMs : 2000);
    const int maxHoldSec = (yfConfig_.maxHoldSec >= 0) ? yfConfig_.maxHoldSec : 0;

    auto startTime = std::chrono::steady_clock::now();
    auto lastSendTime = startTime - sendInterval;
    auto lastPollTime = startTime - std::chrono::milliseconds(200);

    int sendCount = 0;
    int errorCount = 0;
    const int maxErrors = 5;

    auto readIntOID = [&](const std::string& oid, int& out) -> bool {
        bool ok = false;
        snmpHandler_->get(config_.addr, {oid}, [&](bool error, const std::vector<SNMPVarbind>& varbinds) {
            if (error || varbinds.empty()) {
                return;
            }
            int v = 0;
            if (parseIntValue(varbinds[0].value, v)) {
                out = v;
                ok = true;
            }
        });
        return ok;
    };

    std::cout << "[YF_HOLD] Thread started" << std::endl;

    // Один раз перейти в remote mode.
    if (snmpHandler_) {
        snmpHandler_->set(config_.addr, {{SNMPOID::UTC_TYPE2_OPERATION_MODE, ASN_INTEGER, "3"}}, nullptr);
    }

    bool confirmed = false;

    while (!yfStop_) {
        if (!snmpHandler_) {
            break;
        }

        auto now = std::chrono::steady_clock::now();
        auto elapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(now - startTime).count();
        auto elapsedSec = std::chrono::duration_cast<std::chrono::seconds>(now - startTime).count();

        if (maxHoldSec > 0 && elapsedSec >= maxHoldSec) {
            std::cout << "[YF_HOLD] Max hold reached (" << maxHoldSec << "s), stopping" << std::endl;
            break;
        }

        // Poll for confirmation for a bounded time.
        if (!confirmed && elapsedSec <= confirmTimeoutSec && (now - lastPollTime) >= std::chrono::milliseconds(200)) {
            lastPollTime = now;

            int fr = 0;
            if (readIntOID(SNMPOID::UTC_REPLY_FR, fr) && fr != 0) {
                std::cout << "[YF_HOLD] Confirmed: utcReplyFR=" << fr << " (elapsed=" << elapsedMs << "ms)" << std::endl;
                confirmed = true;
                state_.regime = 2;
                state_.algorithm = 0;
            }
        }

        if ((now - lastSendTime) >= sendInterval) {
            lastSendTime = now;

            std::vector<SNMPVarbind> varbinds;
            SNMPVarbind modeVarbind;
            modeVarbind.oid = SNMPOID::UTC_TYPE2_OPERATION_MODE;
            modeVarbind.type = ASN_INTEGER;
            modeVarbind.value = "3";
            varbinds.push_back(modeVarbind);

            SNMPVarbind ffVarbind;
            ffVarbind.oid = SNMPOID::UTC_CONTROL_FF;
            ffVarbind.type = ASN_INTEGER;
            ffVarbind.value = "1";
            varbinds.push_back(ffVarbind);

            sendCount++;
            snmpHandler_->set(config_.addr, varbinds, [&](bool error, const std::vector<SNMPVarbind>&) {
                if (error) {
                    errorCount++;
                    std::cerr << "[YF_HOLD] Send #" << sendCount << " failed (errors=" << errorCount
                              << ", elapsed=" << elapsedMs << "ms)" << std::endl;
                } else {
                    errorCount = 0;
                    // Keep logs light: print occasionally.
                    if (sendCount == 1 || (sendCount % 30) == 0) {
                        std::cout << "[YF_HOLD] Send #" << sendCount << " ok (elapsed=" << elapsedMs << "ms)" << std::endl;
                    }
                }
            });

            if (errorCount >= maxErrors) {
                std::cerr << "[YF_HOLD] Too many errors (" << errorCount << "), stopping ensure thread" << std::endl;
                break;
            }
        }

        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }

    auto totalElapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - startTime).count();

    std::cout << "[YF_HOLD] Thread complete: confirmed=" << (confirmed ? "yes" : "no")
              << ", sends=" << sendCount
              << ", elapsed=" << totalElapsedMs << "ms" << std::endl;

    yfHoldActive_ = false;
}
