#!/usr/bin/env node
/**
 * UTMC/UG405 SNMP Tester
 * Утилита для тестирования SNMP SET/GET команд на дорожных контроллерах
 * 
 * Использование:
 *   node utmc-tester.js --ip 192.168.1.100 --test
 *   node utmc-tester.js --ip 192.168.1.100 --set-phase 3
 *   node utmc-tester.js --ip 192.168.1.100 --scan
 */

const snmp = require('net-snmp');
const { program } = require('commander');
const fs = require('fs');

// ==================== КОНФИГУРАЦИЯ OID ====================
const OID = {
  // Системные
  sysDescr: '1.3.6.1.2.1.1.1.0',
  sysUpTime: '1.3.6.1.2.1.1.3.0',
  
  // UTMC base
  utmc: '1.3.6.1.4.1.13267',
  
  // Full UTC MIB (UG405/Type 2)
  utcType2OperationMode: '1.3.6.1.4.1.13267.3.2.4.1',
  utcControlEntry: '1.3.6.1.4.1.13267.3.2.4.2.1',
  utcControlFn: '1.3.6.1.4.1.13267.3.2.4.2.1.5',      // Force bits
  utcControlLO: '1.3.6.1.4.1.13267.3.2.4.2.1.11',     // Lamps On/Off
  utcControlFF: '1.3.6.1.4.1.13267.3.2.4.2.1.20',     // Flash mode
  
  // Reply objects
  utcReplyEntry: '1.3.6.1.4.1.13267.3.2.5.1.1',
  utcReplyGn: '1.3.6.1.4.1.13267.3.2.5.1.1.3',        // Current stage
  utcReplySDn: '1.3.6.1.4.1.13267.3.2.5.1.1.14',
  utcReplyMC: '1.3.6.1.4.1.13267.3.2.5.1.1.15',
  utcReplyFR: '1.3.6.1.4.1.13267.3.2.5.1.1.36',
  
  // Simple UTC MIB (Type 1)
  utcSimpleControl: '1.3.6.1.4.1.13267.4',
};

// ==================== УТИЛИТЫ ====================

/**
 * Преобразование SCN в различные форматы для OID
 */
function scnToOidSuffix(scn, mode) {
  if (!scn || mode === 'none') return '';
  
  switch (mode) {
    case 'ascii':
      // CO1111 -> .67.79.49.49.49.49
      return '.' + scn.split('').map(c => c.charCodeAt(0)).join('.');
    case 'index':
      // Простой индекс .1
      return '.1';
    case 'suffix':
      // Добавить как есть (для числового SCN)
      return '.' + scn;
    case 'length-prefixed':
      // Формат с длиной: .6.67.79.49.49.49.49
      const chars = scn.split('').map(c => c.charCodeAt(0));
      return '.' + chars.length + '.' + chars.join('.');
    default:
      return '';
  }
}

/**
 * Парсинг hex значения
 */
function parseHexValue(value) {
  if (typeof value === 'string') {
    if (value.startsWith('0x')) {
      return Buffer.from([parseInt(value, 16)]);
    }
    return Buffer.from(value);
  }
  return Buffer.from([value]);
}

/**
 * Форматирование результата для вывода
 */
function formatVarbind(varbind) {
  const typeNames = {
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
  
  let valueStr = varbind.value;
  if (Buffer.isBuffer(varbind.value)) {
    valueStr = `Hex: ${varbind.value.toString('hex').toUpperCase()} | ASCII: "${varbind.value.toString()}"`;
  }
  
  return {
    oid: varbind.oid,
    type: typeNames[varbind.type] || varbind.type,
    value: valueStr
  };
}

// ==================== SNMP ОПЕРАЦИИ ====================

class UtmcTester {
  constructor(options) {
    this.ip = options.ip;
    this.community = options.community || 'UTMC';
    this.scn = options.scn;
    this.scnMode = options.scnMode || 'none';
    this.timeout = options.timeout || 5000;
    this.retries = options.retries || 1;
    this.verbose = options.verbose;
    this.logFile = options.logFile;
    
    this.session = null;
    this.logs = [];
  }
  
  log(message, data = null) {
    const timestamp = new Date().toISOString();
    const entry = { timestamp, message, data };
    this.logs.push(entry);
    
    if (this.verbose) {
      console.log(`[${timestamp}] ${message}`);
      if (data) console.log(JSON.stringify(data, null, 2));
    }
    
    if (this.logFile) {
      fs.appendFileSync(this.logFile, JSON.stringify(entry) + '\n');
    }
  }
  
  connect() {
    this.session = snmp.createSession(this.ip, this.community, {
      timeout: this.timeout,
      retries: this.retries,
      version: snmp.Version2c
    });
    this.log(`Connected to ${this.ip} with community "${this.community}"`);
  }
  
  close() {
    if (this.session) {
      this.session.close();
      this.log('Session closed');
    }
  }
  
  buildOid(baseOid) {
    const suffix = scnToOidSuffix(this.scn, this.scnMode);
    return baseOid + suffix;
  }
  
  // ---- GET операции ----
  
  async get(oids) {
    return new Promise((resolve, reject) => {
      const oidList = Array.isArray(oids) ? oids : [oids];
      this.log(`SNMP GET: ${oidList.join(', ')}`);
      
      this.session.get(oidList, (error, varbinds) => {
        if (error) {
          this.log(`GET Error: ${error.message}`);
          reject(error);
        } else {
          const results = varbinds.map(formatVarbind);
          this.log('GET Response:', results);
          resolve(results);
        }
      });
    });
  }
  
  async walk(oid) {
    return new Promise((resolve, reject) => {
      const results = [];
      this.log(`SNMP WALK: ${oid}`);
      
      this.session.walk(oid, 20, (varbinds) => {
        varbinds.forEach(vb => {
          if (!snmp.isVarbindError(vb)) {
            results.push(formatVarbind(vb));
          }
        });
      }, (error) => {
        if (error) {
          this.log(`WALK Error: ${error.message}`);
          reject(error);
        } else {
          this.log(`WALK completed, found ${results.length} OIDs`);
          resolve(results);
        }
      });
    });
  }
  
  // ---- SET операции ----
  
  async set(varbinds) {
    return new Promise((resolve, reject) => {
      this.log(`SNMP SET:`, varbinds.map(v => ({
        oid: v.oid,
        type: v.type,
        value: Buffer.isBuffer(v.value) ? `0x${v.value.toString('hex')}` : v.value
      })));
      
      this.session.set(varbinds, (error, varbinds) => {
        if (error) {
          this.log(`SET Error: ${error.message}`);
          reject(error);
        } else {
          const results = varbinds.map(formatVarbind);
          this.log('SET Response:', results);
          resolve(results);
        }
      });
    });
  }
  
  // ---- Высокоуровневые команды ----
  
  async testConnection() {
    console.log('\n=== Test Connection ===');
    try {
      const result = await this.get([OID.sysDescr, OID.sysUpTime]);
      console.log('✓ Connection successful!');
      result.forEach(r => {
        console.log(`  ${r.oid}: ${r.value}`);
      });
      return true;
    } catch (e) {
      console.log('✗ Connection failed:', e.message);
      return false;
    }
  }
  
  async getStatus() {
    console.log('\n=== Controller Status ===');
    const oids = [
      this.buildOid(OID.utcType2OperationMode),
      this.buildOid(OID.utcReplyGn),
    ];
    
    try {
      const result = await this.get(oids);
      result.forEach(r => {
        let label = r.oid;
        if (r.oid.includes('.4.1')) label = 'Operation Mode';
        if (r.oid.includes('.5.1.1.3')) label = 'Current Stage (Gn)';
        console.log(`  ${label}: ${r.value}`);
      });
      return result;
    } catch (e) {
      console.log('✗ Failed to get status:', e.message);
      return null;
    }
  }
  
  async setPhase(phase) {
    console.log(`\n=== Set Phase ${phase} ===`);
    
    if (phase < 1 || phase > 7) {
      console.log('✗ Phase must be 1-7');
      return false;
    }
    
    const phaseBit = 1 << (phase - 1);
    const operationModeOid = this.buildOid(OID.utcType2OperationMode);
    const controlFnOid = this.buildOid(OID.utcControlFn);
    
    console.log(`  Operation Mode OID: ${operationModeOid}`);
    console.log(`  Control Fn OID: ${controlFnOid}`);
    console.log(`  Phase bit value: 0x${phaseBit.toString(16).padStart(2, '0')}`);
    
    const varbinds = [
      {
        oid: operationModeOid,
        type: snmp.ObjectType.Integer,
        value: 3  // Remote control mode
      },
      {
        oid: controlFnOid,
        type: snmp.ObjectType.OctetString,
        value: Buffer.from([phaseBit])
      }
    ];
    
    try {
      const result = await this.set(varbinds);
      console.log('✓ Phase set successfully!');
      return result;
    } catch (e) {
      console.log('✗ Failed to set phase:', e.message);
      return null;
    }
  }
  
  async rawSet(oid, value, type = 'OctetString') {
    console.log(`\n=== Raw SET ===`);
    console.log(`  OID: ${oid}`);
    console.log(`  Value: ${value}`);
    console.log(`  Type: ${type}`);
    
    let snmpType, snmpValue;
    
    switch (type.toLowerCase()) {
      case 'integer':
      case 'i':
        snmpType = snmp.ObjectType.Integer;
        snmpValue = parseInt(value);
        break;
      case 'octetstring':
      case 'string':
      case 's':
      case 'x':
        snmpType = snmp.ObjectType.OctetString;
        snmpValue = parseHexValue(value);
        break;
      case 'oid':
      case 'o':
        snmpType = snmp.ObjectType.OID;
        snmpValue = value;
        break;
      default:
        snmpType = snmp.ObjectType.OctetString;
        snmpValue = parseHexValue(value);
    }
    
    try {
      const result = await this.set([{ oid, type: snmpType, value: snmpValue }]);
      console.log('✓ SET successful!');
      return result;
    } catch (e) {
      console.log('✗ SET failed:', e.message);
      return null;
    }
  }
  
  async rawGet(oid) {
    console.log(`\n=== Raw GET ===`);
    console.log(`  OID: ${oid}`);
    
    try {
      const result = await this.get([oid]);
      console.log('✓ GET successful!');
      result.forEach(r => {
        console.log(`  Type: ${r.type}`);
        console.log(`  Value: ${r.value}`);
      });
      return result;
    } catch (e) {
      console.log('✗ GET failed:', e.message);
      return null;
    }
  }
  
  async scan() {
    console.log('\n=== UTMC OID Scan ===');
    console.log(`Walking ${OID.utmc}...`);
    
    try {
      const results = await this.walk(OID.utmc);
      
      console.log(`\nFound ${results.length} OIDs:\n`);
      results.forEach(r => {
        console.log(`${r.oid}`);
        console.log(`  Type: ${r.type}`);
        console.log(`  Value: ${r.value}\n`);
      });
      
      return results;
    } catch (e) {
      console.log('✗ Scan failed:', e.message);
      return null;
    }
  }
  
  async runScenarios(scenarios) {
    console.log('\n=== Running Test Scenarios ===\n');
    const results = [];
    
    for (const scenario of scenarios) {
      console.log(`\n--- ${scenario.name} ---`);
      const scenarioResult = { name: scenario.name, operations: [] };
      
      for (const op of scenario.operations) {
        try {
          let result;
          if (op.type === 'set') {
            const varbind = {
              oid: op.oid,
              type: op.valueType === 'Integer' ? snmp.ObjectType.Integer : snmp.ObjectType.OctetString,
              value: op.valueType === 'Integer' ? op.value : parseHexValue(op.value)
            };
            result = await this.set([varbind]);
            scenarioResult.operations.push({ ...op, status: 'success', result });
            console.log(`  ✓ SET ${op.oid} = ${op.value}`);
          } else if (op.type === 'get') {
            result = await this.get([op.oid]);
            scenarioResult.operations.push({ ...op, status: 'success', result });
            console.log(`  ✓ GET ${op.oid}`);
          }
        } catch (e) {
          scenarioResult.operations.push({ ...op, status: 'error', error: e.message });
          console.log(`  ✗ ${op.type.toUpperCase()} ${op.oid}: ${e.message}`);
        }
        
        // Пауза между операциями
        await new Promise(r => setTimeout(r, 500));
      }
      
      results.push(scenarioResult);
    }
    
    return results;
  }
}

// ==================== CLI ====================

program
  .name('utmc-tester')
  .description('UTMC/UG405 SNMP Testing Utility')
  .version('1.0.0')
  .requiredOption('-i, --ip <address>', 'Controller IP address')
  .option('-c, --community <string>', 'SNMP community string', 'UTMC')
  .option('-s, --scn <string>', 'Site Control Number')
  .option('-m, --scn-mode <mode>', 'SCN mode: none|ascii|index|suffix|length-prefixed', 'none')
  .option('-t, --timeout <ms>', 'SNMP timeout in milliseconds', '5000')
  .option('-r, --retries <n>', 'Number of retries', '1')
  .option('-v, --verbose', 'Verbose output')
  .option('-l, --log-file <path>', 'Log file path')
  .option('--test', 'Test connection')
  .option('--status', 'Get controller status')
  .option('--set-phase <n>', 'Set phase (1-7)')
  .option('--scan', 'Scan UTMC OID tree')
  .option('--raw-get <oid>', 'Raw SNMP GET')
  .option('--raw-set <oid>', 'Raw SNMP SET (use with --value and --type)')
  .option('--value <value>', 'Value for raw SET')
  .option('--type <type>', 'Type for raw SET: Integer|OctetString', 'OctetString')
  .option('--scenarios <file>', 'Run scenarios from JSON file');

program.parse();

const options = program.opts();

async function main() {
  console.log('╔════════════════════════════════════════╗');
  console.log('║    UTMC/UG405 SNMP Tester v1.0.0      ║');
  console.log('╚════════════════════════════════════════╝');
  console.log(`\nTarget: ${options.ip}`);
  console.log(`Community: ${options.community}`);
  if (options.scn) {
    console.log(`SCN: ${options.scn} (mode: ${options.scnMode})`);
  }
  
  const tester = new UtmcTester({
    ip: options.ip,
    community: options.community,
    scn: options.scn,
    scnMode: options.scnMode,
    timeout: parseInt(options.timeout),
    retries: parseInt(options.retries),
    verbose: options.verbose,
    logFile: options.logFile
  });
  
  try {
    tester.connect();
    
    if (options.test) {
      await tester.testConnection();
    }
    
    if (options.status) {
      await tester.getStatus();
    }
    
    if (options.setPhase) {
      await tester.setPhase(parseInt(options.setPhase));
    }
    
    if (options.scan) {
      await tester.scan();
    }
    
    if (options.rawGet) {
      await tester.rawGet(options.rawGet);
    }
    
    if (options.rawSet && options.value) {
      await tester.rawSet(options.rawSet, options.value, options.type);
    }
    
    if (options.scenarios) {
      const scenarios = JSON.parse(fs.readFileSync(options.scenarios, 'utf8'));
      const results = await tester.runScenarios(scenarios);
      console.log('\n=== Scenario Results ===');
      console.log(JSON.stringify(results, null, 2));
    }
    
  } finally {
    tester.close();
  }
}

main().catch(console.error);
