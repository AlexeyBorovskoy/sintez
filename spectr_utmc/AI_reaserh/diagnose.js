#!/usr/bin/env node
/**
 * UTMC Controller Diagnostic Tool
 * Полная диагностика и инвентаризация OID контроллера
 * 
 * Использование:
 *   node diagnose.js --ip 192.168.1.100 --community UTMC
 */

const snmp = require('net-snmp');
const { program } = require('commander');
const fs = require('fs');

// Известные OID для классификации
const KNOWN_OIDS = {
  // System MIB
  '1.3.6.1.2.1.1.1': { name: 'sysDescr', category: 'system' },
  '1.3.6.1.2.1.1.2': { name: 'sysObjectID', category: 'system' },
  '1.3.6.1.2.1.1.3': { name: 'sysUpTime', category: 'system' },
  '1.3.6.1.2.1.1.4': { name: 'sysContact', category: 'system' },
  '1.3.6.1.2.1.1.5': { name: 'sysName', category: 'system' },
  '1.3.6.1.2.1.1.6': { name: 'sysLocation', category: 'system' },
  
  // UTMC Full UTC MIB (Type 2 / UG405)
  '1.3.6.1.4.1.13267.3.2.4.1': { name: 'utcType2OperationMode', category: 'utc-control', writable: true },
  '1.3.6.1.4.1.13267.3.2.4.2.1.5': { name: 'utcControlFn', category: 'utc-control', writable: true, description: 'Force bits (фазы)' },
  '1.3.6.1.4.1.13267.3.2.4.2.1.11': { name: 'utcControlLO', category: 'utc-control', writable: true, description: 'Lamps On/Off' },
  '1.3.6.1.4.1.13267.3.2.4.2.1.20': { name: 'utcControlFF', category: 'utc-control', writable: true, description: 'Flash mode' },
  
  '1.3.6.1.4.1.13267.3.2.5.1.1.3': { name: 'utcReplyGn', category: 'utc-reply', description: 'Current stage' },
  '1.3.6.1.4.1.13267.3.2.5.1.1.14': { name: 'utcReplySDn', category: 'utc-reply' },
  '1.3.6.1.4.1.13267.3.2.5.1.1.15': { name: 'utcReplyMC', category: 'utc-reply' },
  '1.3.6.1.4.1.13267.3.2.5.1.1.36': { name: 'utcReplyFR', category: 'utc-reply', description: 'Current regime' },
  '1.3.6.1.4.1.13267.3.2.5.1.1.45': { name: 'utcReplyDF', category: 'utc-reply' },
  
  // UTMC Simple UTC MIB (Type 1)
  '1.3.6.1.4.1.13267.4': { name: 'utmcSimpleUTC', category: 'utc-simple' },
  
  // Other UTMC
  '1.3.6.1.4.1.13267.5': { name: 'utmcTrafficCounter', category: 'traffic-counter' },
  '1.3.6.1.4.1.13267.6': { name: 'utmcVMS', category: 'vms' },
};

class UtmcDiagnostic {
  constructor(options) {
    this.ip = options.ip;
    this.community = options.community || 'UTMC';
    this.timeout = options.timeout || 10000;
    this.session = null;
    
    this.results = {
      timestamp: new Date().toISOString(),
      controller: {
        ip: this.ip,
        community: this.community
      },
      system: {},
      mibType: null,
      oids: [],
      categories: {},
      recommendations: []
    };
  }
  
  connect() {
    this.session = snmp.createSession(this.ip, this.community, {
      timeout: this.timeout,
      retries: 2,
      version: snmp.Version2c
    });
  }
  
  close() {
    if (this.session) {
      this.session.close();
    }
  }
  
  formatValue(varbind) {
    if (Buffer.isBuffer(varbind.value)) {
      return {
        hex: varbind.value.toString('hex').toUpperCase(),
        ascii: varbind.value.toString().replace(/[^\x20-\x7E]/g, '.'),
        bytes: Array.from(varbind.value)
      };
    }
    return varbind.value;
  }
  
  getTypeName(type) {
    const types = {
      [snmp.ObjectType.Boolean]: 'Boolean',
      [snmp.ObjectType.Integer]: 'Integer',
      [snmp.ObjectType.OctetString]: 'OctetString',
      [snmp.ObjectType.Null]: 'Null',
      [snmp.ObjectType.OID]: 'OID',
      [snmp.ObjectType.Counter]: 'Counter',
      [snmp.ObjectType.Gauge]: 'Gauge',
      [snmp.ObjectType.TimeTicks]: 'TimeTicks',
      [snmp.ObjectType.Opaque]: 'Opaque',
      [snmp.ObjectType.Counter64]: 'Counter64',
    };
    return types[type] || `Unknown(${type})`;
  }
  
  classifyOid(oid) {
    // Точное совпадение
    if (KNOWN_OIDS[oid]) {
      return KNOWN_OIDS[oid];
    }
    
    // Поиск по префиксу (для таблиц с индексами)
    const oidParts = oid.split('.');
    for (let i = oidParts.length; i > 0; i--) {
      const prefix = oidParts.slice(0, i).join('.');
      if (KNOWN_OIDS[prefix]) {
        return {
          ...KNOWN_OIDS[prefix],
          index: oidParts.slice(i).join('.')
        };
      }
    }
    
    // Категоризация по базовому OID
    if (oid.startsWith('1.3.6.1.2.1.1')) return { category: 'system' };
    if (oid.startsWith('1.3.6.1.4.1.13267.3.2.4')) return { category: 'utc-control' };
    if (oid.startsWith('1.3.6.1.4.1.13267.3.2.5')) return { category: 'utc-reply' };
    if (oid.startsWith('1.3.6.1.4.1.13267.3')) return { category: 'utc-full' };
    if (oid.startsWith('1.3.6.1.4.1.13267.4')) return { category: 'utc-simple' };
    if (oid.startsWith('1.3.6.1.4.1.13267')) return { category: 'utmc-other' };
    
    return { category: 'unknown' };
  }
  
  async get(oids) {
    return new Promise((resolve, reject) => {
      this.session.get(oids, (error, varbinds) => {
        if (error) reject(error);
        else resolve(varbinds);
      });
    });
  }
  
  async walk(oid) {
    return new Promise((resolve, reject) => {
      const results = [];
      this.session.walk(oid, 50, (varbinds) => {
        varbinds.forEach(vb => {
          if (!snmp.isVarbindError(vb)) {
            results.push(vb);
          }
        });
      }, (error) => {
        if (error) reject(error);
        else resolve(results);
      });
    });
  }
  
  async getSystemInfo() {
    console.log('📋 Получение системной информации...');
    
    try {
      const systemOids = [
        '1.3.6.1.2.1.1.1.0', // sysDescr
        '1.3.6.1.2.1.1.2.0', // sysObjectID
        '1.3.6.1.2.1.1.3.0', // sysUpTime
        '1.3.6.1.2.1.1.4.0', // sysContact
        '1.3.6.1.2.1.1.5.0', // sysName
        '1.3.6.1.2.1.1.6.0', // sysLocation
      ];
      
      const results = await this.get(systemOids);
      
      results.forEach(vb => {
        const name = this.classifyOid(vb.oid.replace('.0', '')).name;
        this.results.system[name] = this.formatValue(vb);
      });
      
      console.log('  ✓ Системная информация получена');
      return true;
    } catch (e) {
      console.log('  ✗ Ошибка:', e.message);
      return false;
    }
  }
  
  async scanUtmcTree() {
    console.log('🔍 Сканирование UTMC дерева (1.3.6.1.4.1.13267)...');
    
    try {
      const results = await this.walk('1.3.6.1.4.1.13267');
      
      console.log(`  ✓ Найдено ${results.length} OID`);
      
      results.forEach(vb => {
        const classification = this.classifyOid(vb.oid);
        const entry = {
          oid: vb.oid,
          type: this.getTypeName(vb.type),
          value: this.formatValue(vb),
          ...classification
        };
        
        this.results.oids.push(entry);
        
        // Группировка по категориям
        if (!this.results.categories[classification.category]) {
          this.results.categories[classification.category] = [];
        }
        this.results.categories[classification.category].push(entry);
      });
      
      // Определение типа MIB
      if (this.results.categories['utc-control'] || this.results.categories['utc-reply']) {
        this.results.mibType = 'Full UTC MIB (Type 2 / UG405)';
      } else if (this.results.categories['utc-simple']) {
        this.results.mibType = 'Simple UTC MIB (Type 1)';
      } else {
        this.results.mibType = 'Unknown';
      }
      
      return true;
    } catch (e) {
      console.log('  ✗ Ошибка:', e.message);
      return false;
    }
  }
  
  async testControlAccess() {
    console.log('🔧 Проверка доступа к объектам управления...');
    
    const controlOids = [
      '1.3.6.1.4.1.13267.3.2.4.1',      // operationMode
      '1.3.6.1.4.1.13267.3.2.4.2.1.5',  // controlFn без индекса
      '1.3.6.1.4.1.13267.3.2.4.2.1.5.1', // controlFn с .1
    ];
    
    for (const oid of controlOids) {
      try {
        const result = await this.get([oid]);
        console.log(`  ✓ ${oid} - доступен`);
        
        this.results.recommendations.push({
          oid,
          status: 'accessible',
          note: 'OID доступен для чтения'
        });
      } catch (e) {
        console.log(`  ✗ ${oid} - недоступен (${e.message})`);
        
        this.results.recommendations.push({
          oid,
          status: 'not_accessible',
          error: e.message
        });
      }
    }
  }
  
  generateReport() {
    console.log('\n📊 ОТЧЁТ О ДИАГНОСТИКЕ\n');
    console.log('═'.repeat(60));
    
    // Системная информация
    console.log('\n🖥️  СИСТЕМА');
    console.log('-'.repeat(40));
    Object.entries(this.results.system).forEach(([key, value]) => {
      const displayValue = typeof value === 'object' ? value.ascii || JSON.stringify(value) : value;
      console.log(`  ${key}: ${displayValue}`);
    });
    
    // Тип MIB
    console.log('\n📚 ТИП MIB');
    console.log('-'.repeat(40));
    console.log(`  ${this.results.mibType}`);
    
    // Статистика по категориям
    console.log('\n📈 СТАТИСТИКА OID');
    console.log('-'.repeat(40));
    Object.entries(this.results.categories).forEach(([category, oids]) => {
      console.log(`  ${category}: ${oids.length} OID`);
    });
    
    // Ключевые объекты управления
    if (this.results.categories['utc-control']) {
      console.log('\n🎛️  ОБЪЕКТЫ УПРАВЛЕНИЯ');
      console.log('-'.repeat(40));
      this.results.categories['utc-control'].forEach(entry => {
        const name = entry.name || entry.oid;
        const desc = entry.description || '';
        console.log(`  ${name}${entry.index ? '.' + entry.index : ''}`);
        console.log(`    OID: ${entry.oid}`);
        console.log(`    Тип: ${entry.type}`);
        console.log(`    Значение: ${JSON.stringify(entry.value)}`);
        if (desc) console.log(`    Описание: ${desc}`);
        console.log();
      });
    }
    
    // Объекты Reply
    if (this.results.categories['utc-reply']) {
      console.log('\n📩 ОБЪЕКТЫ REPLY (состояние)');
      console.log('-'.repeat(40));
      this.results.categories['utc-reply'].forEach(entry => {
        const name = entry.name || entry.oid;
        console.log(`  ${name}: ${JSON.stringify(entry.value)}`);
      });
    }
    
    // Рекомендации
    console.log('\n💡 РЕКОМЕНДАЦИИ');
    console.log('-'.repeat(40));
    
    const accessibleControl = this.results.recommendations.filter(r => 
      r.status === 'accessible' && r.oid.includes('.4.2.1.5')
    );
    
    if (accessibleControl.length > 0) {
      console.log(`  ✓ Рекомендуемый OID для SET_PHASE: ${accessibleControl[0].oid}`);
    } else {
      console.log('  ⚠️  Не найден доступный OID для управления фазами');
      console.log('     Попробуйте выполнить SNMP WALK и найти правильный формат');
    }
    
    console.log('\n' + '═'.repeat(60));
  }
  
  async run() {
    console.log('╔════════════════════════════════════════════════════════════╗');
    console.log('║         UTMC Controller Diagnostic Tool                     ║');
    console.log('╚════════════════════════════════════════════════════════════╝');
    console.log(`\nЦель: ${this.ip}`);
    console.log(`Community: ${this.community}\n`);
    
    this.connect();
    
    try {
      await this.getSystemInfo();
      await this.scanUtmcTree();
      await this.testControlAccess();
      this.generateReport();
      
      return this.results;
    } finally {
      this.close();
    }
  }
}

// CLI
program
  .name('diagnose')
  .description('UTMC Controller Diagnostic Tool')
  .version('1.0.0')
  .requiredOption('-i, --ip <address>', 'Controller IP address')
  .option('-c, --community <string>', 'SNMP community string', 'UTMC')
  .option('-t, --timeout <ms>', 'SNMP timeout in milliseconds', '10000')
  .option('-o, --output <file>', 'Output JSON report to file');

program.parse();

const options = program.opts();

async function main() {
  const diagnostic = new UtmcDiagnostic({
    ip: options.ip,
    community: options.community,
    timeout: parseInt(options.timeout)
  });
  
  const results = await diagnostic.run();
  
  if (options.output) {
    fs.writeFileSync(options.output, JSON.stringify(results, null, 2));
    console.log(`\n📄 Отчёт сохранён в ${options.output}`);
  }
}

main().catch(console.error);
