#!/usr/bin/env node
/**
 * Простой анализ состояния контроллера
 */

const snmp = require('net-snmp');

const CONTROLLER_IP = process.argv[2] || '192.168.75.150';
const COMMUNITY = process.argv[3] || 'UTMC';

const session = snmp.createSession(CONTROLLER_IP, COMMUNITY);

// Основные OID
const oids = [
    { key: 'OPERATION_MODE', oid: '1.3.6.1.4.1.13267.3.2.4.1' },
    { key: 'CURRENT_STAGE_GN', oid: '1.3.6.1.4.1.13267.3.2.5.1.1.3' },
    { key: 'STAGE_LENGTH', oid: '1.3.6.1.4.1.13267.3.2.5.1.1.4' },
    { key: 'STAGE_COUNTER', oid: '1.3.6.1.4.1.13267.3.2.5.1.1.5' },
    { key: 'CYCLE_COUNTER', oid: '1.3.6.1.4.1.13267.3.2.5.1.1.6' },
    { key: 'TRANSITION', oid: '1.3.6.1.4.1.13267.3.2.5.1.1.7' },
    { key: 'FLASHING_MODE_FR', oid: '1.3.6.1.4.1.13267.3.2.5.1.1.36' },
];

function hexToPhase(hexStr) {
    if (!hexStr) return [];
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
    session.get([oid], (error, varbinds) => {
        if (error) {
            callback(error, null);
            return;
        }
        const varbind = varbinds[0];
        if (snmp.isVarbindError(varbind)) {
            callback(new Error(snmp.varbindError(varbind)), null);
        } else {
            callback(null, varbind.value);
        }
    });
}

function getAllValues(callback) {
    const oidList = oids.map(o => o.oid);
    const results = {};
    let completed = 0;
    
    oidList.forEach((oid, index) => {
        getValue(oid, (error, value) => {
            const key = oids[index].key;
            if (error) {
                if (error.message.includes('NoSuchName')) {
                    results[key] = null;
                } else {
                    results[key] = { error: error.message };
                }
            } else {
                results[key] = value;
            }
            
            completed++;
            if (completed === oidList.length) {
                callback(null, results);
            }
        });
    });
}

function analyzeState(data) {
    const analysis = {
        canActivateFlashing: false,
        reasons: [],
        recommendations: []
    };
    
    // Режим работы
    if (data.OPERATION_MODE === null || data.OPERATION_MODE.error) {
        analysis.reasons.push('⚠ Не удалось получить режим работы');
    } else {
        const mode = data.OPERATION_MODE;
        const modes = { 0: 'Local', 1: 'Standalone', 2: 'Monitor', 3: 'UTC Control' };
        analysis.reasons.push(`Режим работы: ${modes[mode] || `Unknown (${mode})`}`);
        
        if (mode !== 3) {
            analysis.reasons.push(`⚠ Контроллер не в режиме UTC Control (текущий: ${mode})`);
            analysis.recommendations.push('Перевести в режим UTC Control (3) перед активацией мигания');
        } else {
            analysis.reasons.push('✓ Контроллер в режиме UTC Control');
        }
    }
    
    // Текущая фаза
    if (data.CURRENT_STAGE_GN === null || data.CURRENT_STAGE_GN.error) {
        analysis.reasons.push('⚠ Не удалось получить текущую фазу');
    } else {
        const hex = Buffer.isBuffer(data.CURRENT_STAGE_GN) 
            ? data.CURRENT_STAGE_GN.toString('hex') 
            : String(data.CURRENT_STAGE_GN);
        const phases = hexToPhase(hex);
        analysis.reasons.push(`Текущая фаза: 0x${hex} → ${phases.length > 0 && phases[0] !== 0 ? `Фаза ${phases.join(', ')}` : 'нет активной фазы'}`);
        
        if (phases.length === 0 || phases[0] === 0) {
            analysis.reasons.push('⚠ Нет активной фазы');
            analysis.recommendations.push('Дождаться активации фазы');
        }
    }
    
    // Длительность фазы
    if (data.STAGE_LENGTH && !data.STAGE_LENGTH.error) {
        analysis.reasons.push(`Длительность фазы: ${data.STAGE_LENGTH} сек`);
    }
    
    // Счётчик фазы
    if (data.STAGE_COUNTER && !data.STAGE_COUNTER.error) {
        analysis.reasons.push(`Счётчик фазы: ${data.STAGE_COUNTER} сек`);
        
        if (data.STAGE_LENGTH && !data.STAGE_LENGTH.error) {
            const remaining = data.STAGE_LENGTH - data.STAGE_COUNTER;
            analysis.reasons.push(`Осталось в фазе: ${remaining} сек`);
            
            // Минимальный период = 50% от длительности
            const minPeriod = Math.floor(data.STAGE_LENGTH * 0.5);
            if (data.STAGE_COUNTER < minPeriod) {
                analysis.reasons.push(`⚠ Минимальный период не истёк (требуется: ${minPeriod} сек, прошло: ${data.STAGE_COUNTER} сек)`);
                analysis.recommendations.push(`Дождаться истечения минимального периода (ещё ${minPeriod - data.STAGE_COUNTER} сек)`);
            } else {
                analysis.reasons.push(`✓ Минимальный период истёк`);
            }
        }
    }
    
    // Переходные процессы
    if (data.TRANSITION !== null && !data.TRANSITION.error) {
        if (data.TRANSITION !== 0) {
            analysis.reasons.push(`⚠ Контроллер в переходном процессе (transition=${data.TRANSITION})`);
            analysis.recommendations.push('Дождаться завершения переходного процесса');
        } else {
            analysis.reasons.push('✓ Нет переходных процессов');
        }
    }
    
    // Режим мигания
    if (data.FLASHING_MODE_FR !== null && !data.FLASHING_MODE_FR.error) {
        if (data.FLASHING_MODE_FR === 1) {
            analysis.reasons.push('⚠ Мигание уже активно!');
            analysis.recommendations.push('Сначала отключить текущее мигание');
        } else {
            analysis.reasons.push('✓ Мигание не активно');
        }
    }
    
    // Итоговая оценка
    const blockingIssues = analysis.reasons.filter(r => r.startsWith('⚠'));
    if (blockingIssues.length === 0 && data.OPERATION_MODE === 3) {
        analysis.canActivateFlashing = true;
        analysis.reasons.push('✓ Все условия выполнены, можно активировать мигание');
    } else if (blockingIssues.length > 0) {
        analysis.reasons.push('✗ Условия для активации мигания не выполнены');
    }
    
    return analysis;
}

function printReport(data, analysis) {
    console.log('\n╔════════════════════════════════════════════════════════════╗');
    console.log('║     Анализ состояния контроллера перед активацией      ║');
    console.log('║              жёлтого мигания (SetAF)                      ║');
    console.log('╚════════════════════════════════════════════════════════════╝\n');
    
    console.log('📊 ТЕКУЩЕЕ СОСТОЯНИЕ:\n');
    
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
        console.log('\n  Стратегия активации:');
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

getAllValues((error, data) => {
    if (error) {
        console.error(`Ошибка: ${error.message}`);
        process.exit(1);
    }
    
    const analysis = analyzeState(data);
    printReport(data, analysis);
    
    session.close();
});
