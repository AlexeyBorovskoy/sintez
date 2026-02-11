#!/usr/bin/env node
/**
 * Диагностический скрипт для анализа состояния контроллера
 * перед активацией жёлтого мигания
 */

const snmp = require('net-snmp');
const readline = require('readline');

const CONTROLLER_IP = process.argv[2] || '192.168.75.150';
const COMMUNITY = process.argv[3] || 'UTMC';

// OID константы
const OIDS = {
    // Режим работы
    OPERATION_MODE: '1.3.6.1.4.1.13267.3.2.4.1',
    
    // Текущая фаза (Gn)
    CURRENT_STAGE_GN: '1.3.6.1.4.1.13267.3.2.5.1.1.3',
    
    // Длительность текущей фазы
    STAGE_LENGTH: '1.3.6.1.4.1.13267.3.2.5.1.1.4',
    
    // Счётчик текущей фазы
    STAGE_COUNTER: '1.3.6.1.4.1.13267.3.2.5.1.1.5',
    
    // Счётчик цикла
    CYCLE_COUNTER: '1.3.6.1.4.1.13267.3.2.5.1.1.6',
    
    // Переходные процессы
    TRANSITION: '1.3.6.1.4.1.13267.3.2.5.1.1.7',
    
    // Режим мигания (FR)
    FLASHING_MODE_FR: '1.3.6.1.4.1.13267.3.2.5.1.1.36',
    
    // Контроль мигания (FF)
    CONTROL_FF: '1.3.6.1.4.1.13267.3.2.4.2.1.20',
    
    // Время контроллера
    TIME: '1.3.6.1.4.1.13267.3.2.5.1.1.1',
    
    // Ошибки
    ERRORS: '1.3.6.1.4.1.13267.3.2.5.1.1.8',
    
    // Предупреждения
    WARNINGS: '1.3.6.1.4.1.13267.3.2.5.1.1.9',
};

const session = snmp.createSession(CONTROLLER_IP, COMMUNITY);

function hexToPhase(hexStr) {
    const hex = hexStr.replace(/^0x/i, '').replace(/\s+/g, '');
    const value = parseInt(hex, 16);
    
    const phases = [];
    for (let i = 0; i < 8; i++) {
        if (value & (1 << i)) {
            phases.push(i + 1);
        }
    }
    
    return phases.length > 0 ? phases : [0];
}

function getValue(oid, callback) {
    const oids = [oid];
    session.get(oids, (error, varbinds) => {
        if (error) {
            callback(error, null);
        } else {
            const varbind = varbinds[0];
            if (snmp.isVarbindError(varbind)) {
                callback(new Error(snmp.varbindError(varbind)), null);
            } else {
                callback(null, varbind.value);
            }
        }
    });
}

function getAllValues(callback) {
    const oids = Object.values(OIDS);
    session.get(oids, (error, varbinds) => {
        if (error) {
            callback(error, null);
            return;
        }
        
        const result = {};
        let index = 0;
        for (const [key, oid] of Object.entries(OIDS)) {
            const varbind = varbinds[index++];
            if (snmp.isVarbindError(varbind)) {
                result[key] = { error: snmp.varbindError(varbind) };
            } else {
                result[key] = varbind.value;
            }
        }
        
        callback(null, result);
    });
}

function formatValue(key, value) {
    if (value === null || value === undefined) {
        return 'N/A';
    }
    
    if (typeof value === 'object' && value.error) {
        return `ERROR: ${value.error}`;
    }
    
    switch (key) {
        case 'CURRENT_STAGE_GN':
            if (typeof value === 'string' || Buffer.isBuffer(value)) {
                const hex = Buffer.isBuffer(value) ? value.toString('hex') : value;
                const phases = hexToPhase(hex);
                return `0x${hex} → Фазы: ${phases.join(', ') || 'нет'}`;
            }
            return String(value);
            
        case 'OPERATION_MODE':
            const modes = {
                0: 'Local (0)',
                1: 'Standalone (1)',
                2: 'Monitor (2)',
                3: 'UTC Control (3)'
            };
            return `${modes[value] || `Unknown (${value})`}`;
            
        case 'TRANSITION':
            return value === 0 ? 'Нет (0)' : `Да (${value})`;
            
        case 'FLASHING_MODE_FR':
            return value === 1 ? '✓ АКТИВНО (1)' : `Не активно (${value})`;
            
        case 'STAGE_LENGTH':
        case 'STAGE_COUNTER':
        case 'CYCLE_COUNTER':
            return `${value} (0x${value.toString(16)})`;
            
        case 'TIME':
            if (typeof value === 'number') {
                const hours = Math.floor(value / 3600);
                const minutes = Math.floor((value % 3600) / 60);
                const seconds = value % 60;
                return `${hours.toString().padStart(2, '0')}:${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
            }
            return String(value);
            
        default:
            if (Buffer.isBuffer(value)) {
                return `0x${value.toString('hex')}`;
            }
            return String(value);
    }
}

function analyzeState(data) {
    const analysis = {
        canActivateFlashing: false,
        reasons: [],
        recommendations: []
    };
    
    // Проверка режима работы
    if (data.OPERATION_MODE !== 3) {
        analysis.reasons.push(`Контроллер не в режиме UTC Control (текущий режим: ${data.OPERATION_MODE})`);
        analysis.recommendations.push('Перевести контроллер в режим UTC Control (3) перед активацией мигания');
    } else {
        analysis.reasons.push('✓ Контроллер в режиме UTC Control');
    }
    
    // Проверка текущей фазы
    const currentPhaseHex = typeof data.CURRENT_STAGE_GN === 'string' 
        ? data.CURRENT_STAGE_GN 
        : (Buffer.isBuffer(data.CURRENT_STAGE_GN) ? data.CURRENT_STAGE_GN.toString('hex') : '');
    const phases = hexToPhase(currentPhaseHex);
    
    if (phases.length === 0 || phases[0] === 0) {
        analysis.reasons.push('⚠ Нет активной фазы');
        analysis.recommendations.push('Дождаться активации фазы');
    } else {
        analysis.reasons.push(`✓ Активная фаза: ${phases.join(', ')}`);
    }
    
    // Проверка переходных процессов
    if (data.TRANSITION !== 0) {
        analysis.reasons.push(`⚠ Контроллер в переходном процессе (transition=${data.TRANSITION})`);
        analysis.recommendations.push('Дождаться завершения переходного процесса');
    } else {
        analysis.reasons.push('✓ Нет переходных процессов');
    }
    
    // Проверка длительности фазы
    if (data.STAGE_LENGTH && typeof data.STAGE_LENGTH === 'number') {
        const stageLengthSec = data.STAGE_LENGTH;
        analysis.reasons.push(`Длительность фазы: ${stageLengthSec} сек`);
        
        if (data.STAGE_COUNTER && typeof data.STAGE_COUNTER === 'number') {
            const stageCounterSec = data.STAGE_COUNTER;
            const remainingSec = stageLengthSec - stageCounterSec;
            
            analysis.reasons.push(`Счётчик фазы: ${stageCounterSec} сек (осталось: ${remainingSec} сек)`);
            
            // Минимальный период работы фазы обычно составляет часть от общей длительности
            // Предполагаем, что минимальный период = 50% от длительности фазы
            const minPeriod = Math.floor(stageLengthSec * 0.5);
            
            if (stageCounterSec < minPeriod) {
                analysis.reasons.push(`⚠ Минимальный период работы фазы не истёк (требуется: ${minPeriod} сек, прошло: ${stageCounterSec} сек)`);
                analysis.recommendations.push(`Дождаться истечения минимального периода (ещё ${minPeriod - stageCounterSec} сек)`);
            } else {
                analysis.reasons.push(`✓ Минимальный период работы фазы истёк`);
            }
        }
    }
    
    // Проверка текущего состояния мигания
    if (data.FLASHING_MODE_FR === 1) {
        analysis.reasons.push('⚠ Мигание уже активно!');
        analysis.recommendations.push('Сначала отключить текущее мигание');
    }
    
    // Итоговая оценка
    const blockingIssues = analysis.reasons.filter(r => r.startsWith('⚠') || r.includes('не в режиме'));
    if (blockingIssues.length === 0 && data.OPERATION_MODE === 3) {
        analysis.canActivateFlashing = true;
        analysis.reasons.push('✓ Все условия выполнены, можно активировать мигание');
    } else {
        analysis.reasons.push('✗ Условия для активации мигания не выполнены');
    }
    
    return analysis;
}

function printReport(data, analysis) {
    console.log('\n╔════════════════════════════════════════════════════════════╗');
    console.log('║     Анализ состояния контроллера перед активацией      ║');
    console.log('║              жёлтого мигания (SetAF)                      ║');
    console.log('╚════════════════════════════════════════════════════════════╝\n');
    
    console.log('📊 ТЕКУЩЕЕ СОСТОЯНИЕ КОНТРОЛЛЕРА:\n');
    
    console.log('Режим работы:');
    console.log(`  ${formatValue('OPERATION_MODE', data.OPERATION_MODE)}\n`);
    
    console.log('Текущая фаза:');
    console.log(`  ${formatValue('CURRENT_STAGE_GN', data.CURRENT_STAGE_GN)}\n`);
    
    if (data.STAGE_LENGTH && !data.STAGE_LENGTH.error) {
        console.log('Длительность фазы:');
        console.log(`  ${formatValue('STAGE_LENGTH', data.STAGE_LENGTH)}\n`);
    }
    
    if (data.STAGE_COUNTER && !data.STAGE_COUNTER.error) {
        console.log('Счётчик текущей фазы:');
        console.log(`  ${formatValue('STAGE_COUNTER', data.STAGE_COUNTER)}\n`);
    }
    
    if (data.CYCLE_COUNTER && !data.CYCLE_COUNTER.error) {
        console.log('Счётчик цикла:');
        console.log(`  ${formatValue('CYCLE_COUNTER', data.CYCLE_COUNTER)}\n`);
    }
    
    console.log('Переходные процессы:');
    console.log(`  ${formatValue('TRANSITION', data.TRANSITION)}\n`);
    
    console.log('Режим мигания (utcReplyFR):');
    console.log(`  ${formatValue('FLASHING_MODE_FR', data.FLASHING_MODE_FR)}\n`);
    
    if (data.TIME && !data.TIME.error) {
        console.log('Время контроллера:');
        console.log(`  ${formatValue('TIME', data.TIME)}\n`);
    }
    
    if (data.ERRORS && !data.ERRORS.error) {
        console.log('Ошибки:');
        console.log(`  ${formatValue('ERRORS', data.ERRORS)}\n`);
    }
    
    if (data.WARNINGS && !data.WARNINGS.error) {
        console.log('Предупреждения:');
        console.log(`  ${formatValue('WARNINGS', data.WARNINGS)}\n`);
    }
    
    console.log('╔════════════════════════════════════════════════════════════╗');
    console.log('║                    АНАЛИЗ УСЛОВИЙ                          ║');
    console.log('╚════════════════════════════════════════════════════════════╝\n');
    
    analysis.reasons.forEach(reason => {
        if (reason.startsWith('✓')) {
            console.log(`  ${reason}`);
        } else if (reason.startsWith('⚠')) {
            console.log(`  ${reason}`);
        } else if (reason.startsWith('✗')) {
            console.log(`  ${reason}`);
        } else {
            console.log(`  • ${reason}`);
        }
    });
    
    console.log('\n╔════════════════════════════════════════════════════════════╗');
    console.log('║                  РЕКОМЕНДАЦИИ                              ║');
    console.log('╚════════════════════════════════════════════════════════════╝\n');
    
    if (analysis.recommendations.length === 0) {
        console.log('  ✓ Все условия выполнены, можно активировать мигание');
    } else {
        analysis.recommendations.forEach((rec, i) => {
            console.log(`  ${i + 1}. ${rec}`);
        });
    }
    
    console.log('\n╔════════════════════════════════════════════════════════════╗');
    console.log('║                    ВЫВОД                                   ║');
    console.log('╚════════════════════════════════════════════════════════════╝\n');
    
    if (analysis.canActivateFlashing) {
        console.log('  ✅ МОЖНО АКТИВИРОВАТЬ ЖЁЛТОЕ МИГАНИЕ');
        console.log('\n  Рекомендуемая стратегия:');
        console.log('    1. Убедиться, что контроллер в режиме UTC Control (3)');
        console.log('    2. Начать удержание команды SET utcControlFF=1');
        console.log('    3. Удерживать команду минимум 10 секунд (рекомендуется 60 сек)');
        console.log('    4. Команда должна быть активна во время "nominated stage"');
    } else {
        console.log('  ❌ НЕ РЕКОМЕНДУЕТСЯ АКТИВИРОВАТЬ МИГАНИЕ СЕЙЧАС');
        console.log('\n  Выполните рекомендации выше перед активацией');
    }
    
    console.log('');
}

function monitorChanges(intervalMs = 5000) {
    console.log(`\n📡 Мониторинг изменений состояния (интервал: ${intervalMs/1000} сек)...\n`);
    console.log('Нажмите Ctrl+C для остановки\n');
    
    let previousState = null;
    
    const monitor = setInterval(() => {
        getAllValues((error, data) => {
            if (error) {
                console.error(`Ошибка получения данных: ${error.message}`);
                return;
            }
            
            const timestamp = new Date().toLocaleTimeString();
            const phaseHex = typeof data.CURRENT_STAGE_GN === 'string' 
                ? data.CURRENT_STAGE_GN 
                : (Buffer.isBuffer(data.CURRENT_STAGE_GN) ? data.CURRENT_STAGE_GN.toString('hex') : '');
            const phases = hexToPhase(phaseHex);
            const phaseStr = phases.length > 0 ? phases.join(',') : 'нет';
            
            const state = {
                mode: data.OPERATION_MODE,
                phase: phaseStr,
                transition: data.TRANSITION,
                flashing: data.FLASHING_MODE_FR,
                stageCounter: data.STAGE_COUNTER
            };
            
            if (previousState && JSON.stringify(state) !== JSON.stringify(previousState)) {
                console.log(`\n[${timestamp}] ИЗМЕНЕНИЕ СОСТОЯНИЯ:`);
                if (state.mode !== previousState.mode) {
                    console.log(`  Режим: ${previousState.mode} → ${state.mode}`);
                }
                if (state.phase !== previousState.phase) {
                    console.log(`  Фаза: ${previousState.phase} → ${state.phase}`);
                }
                if (state.transition !== previousState.transition) {
                    console.log(`  Переход: ${previousState.transition} → ${state.transition}`);
                }
                if (state.flashing !== previousState.flashing) {
                    console.log(`  Мигание: ${previousState.flashing} → ${state.flashing}`);
                }
            }
            
            previousState = state;
            
            // Краткий статус
            process.stdout.write(`\r[${timestamp}] Режим:${state.mode} Фаза:${state.phase} Переход:${state.transition} Мигание:${state.flashing} Счётчик:${state.stageCounter || 'N/A'}`);
        });
    }, intervalMs);
    
    process.on('SIGINT', () => {
        clearInterval(monitor);
        console.log('\n\nМониторинг остановлен');
        session.close();
        process.exit(0);
    });
}

// Главная функция
const command = process.argv[4] || 'analyze';

if (command === 'monitor') {
    getAllValues((error, data) => {
        if (error) {
            console.error(`Ошибка: ${error.message}`);
            process.exit(1);
        }
        
        const analysis = analyzeState(data);
        printReport(data, analysis);
        
        monitorChanges(5000);
    });
} else {
    getAllValues((error, data) => {
        if (error) {
            console.error(`Ошибка: ${error.message}`);
            process.exit(1);
        }
        
        const analysis = analyzeState(data);
        printReport(data, analysis);
        
        session.close();
    });
}
