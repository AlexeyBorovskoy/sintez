#!/usr/bin/env node
/**
 * ROS Discovery Tool
 * Сбор информации о ROS пакетах и сервисах через SNMP и сетевые протоколы
 */

const snmp = require('net-snmp');
const http = require('http');
const { program } = require('commander');

// OID для системной информации
const SYSTEM_OIDS = {
  sysDescr: '1.3.6.1.2.1.1.1.0',
  sysName: '1.3.6.1.2.1.1.5.0',
  sysLocation: '1.3.6.1.2.1.1.6.0',
  sysUpTime: '1.3.6.1.2.1.1.3.0',
};

class ROSDiscovery {
  constructor(options) {
    this.ip = options.ip;
    this.community = options.community || 'UTMC';
    this.session = null;
  }

  connect() {
    this.session = snmp.createSession(this.ip, this.community, {
      timeout: 10000,
      retries: 2,
      version: snmp.Version2c
    });
  }

  close() {
    if (this.session) {
      this.session.close();
    }
  }

  async getSystemInfo() {
    return new Promise((resolve, reject) => {
      const oids = Object.values(SYSTEM_OIDS);
      this.session.get(oids, (error, varbinds) => {
        if (error) {
          reject(error);
        } else {
          const info = {};
          varbinds.forEach((vb, index) => {
            if (!snmp.isVarbindError(vb)) {
              const key = Object.keys(SYSTEM_OIDS)[index];
              info[key] = Buffer.isBuffer(vb.value) ? vb.value.toString() : vb.value;
            }
          });
          resolve(info);
        }
      });
    });
  }

  async walkOIDTree(baseOID) {
    return new Promise((resolve, reject) => {
      const results = [];
      this.session.walk(baseOID, 50, (varbinds) => {
        varbinds.forEach(vb => {
          if (!snmp.isVarbindError(vb)) {
            results.push({
              oid: vb.oid,
              type: vb.type,
              value: Buffer.isBuffer(vb.value) ? vb.value.toString() : vb.value
            });
          }
        });
      }, (error) => {
        if (error) reject(error);
        else resolve(results);
      });
    });
  }

  async checkHTTP() {
    return new Promise((resolve) => {
      const req = http.get(`http://${this.ip}`, { timeout: 3000 }, (res) => {
        let data = '';
        res.on('data', chunk => data += chunk);
        res.on('end', () => {
          resolve({
            status: res.statusCode,
            headers: res.headers,
            body: data.substring(0, 500)
          });
        });
      });
      req.on('error', () => resolve(null));
      req.on('timeout', () => {
        req.destroy();
        resolve(null);
      });
    });
  }

  async discover() {
    console.log('╔════════════════════════════════════════════════════════════╗');
    console.log('║         ROS Discovery Tool                                 ║');
    console.log('╚════════════════════════════════════════════════════════════╝');
    console.log(`\nTarget: ${this.ip}`);
    console.log(`Community: ${this.community}\n`);

    this.connect();

    try {
      // Системная информация
      console.log('📋 Получение системной информации...');
      const sysInfo = await this.getSystemInfo();
      console.log('  ✓ Системная информация получена\n');
      
      Object.entries(sysInfo).forEach(([key, value]) => {
        console.log(`  ${key}: ${value}`);
      });

      // Проверка HTTP
      console.log('\n🌐 Проверка HTTP сервисов...');
      const httpInfo = await this.checkHTTP();
      if (httpInfo) {
        console.log(`  ✓ HTTP сервер доступен (статус: ${httpInfo.status})`);
        if (httpInfo.headers.server) {
          console.log(`  Server: ${httpInfo.headers.server}`);
        }
        if (httpInfo.body) {
          console.log(`  Response preview: ${httpInfo.body.substring(0, 100)}...`);
        }
      } else {
        console.log('  ✗ HTTP сервер недоступен');
      }

      // Сканирование UTMC дерева для поиска ROS информации
      console.log('\n🔍 Сканирование UTMC OID дерева...');
      try {
        const utmcOIDs = await this.walkOIDTree('1.3.6.1.4.1.13267');
        console.log(`  ✓ Найдено ${utmcOIDs.length} OID`);
        
        // Поиск упоминаний ROS
        const rosRelated = utmcOIDs.filter(oid => {
          const value = String(oid.value).toLowerCase();
          return value.includes('ros') || 
                 value.includes('package') || 
                 value.includes('service') ||
                 value.includes('node');
        });
        
        if (rosRelated.length > 0) {
          console.log(`\n  🎯 Найдено ${rosRelated.length} OID, связанных с ROS:`);
          rosRelated.slice(0, 10).forEach(oid => {
            console.log(`    ${oid.oid}: ${String(oid.value).substring(0, 80)}`);
          });
        }
      } catch (e) {
        console.log(`  ⚠️  Ошибка сканирования: ${e.message}`);
      }

      // Анализ системной информации на предмет ROS
      console.log('\n🤖 Анализ на наличие ROS...');
      const sysDescr = String(sysInfo.sysDescr || '').toLowerCase();
      const sysName = String(sysInfo.sysName || '').toLowerCase();
      
      const rosIndicators = [];
      if (sysDescr.includes('ros')) rosIndicators.push('ROS упоминается в sysDescr');
      if (sysName.includes('ros')) rosIndicators.push('ROS упоминается в sysName');
      if (sysDescr.includes('raspberry')) rosIndicators.push('Raspberry Pi обнаружен');
      if (sysDescr.includes('linux')) rosIndicators.push('Linux система');
      
      if (rosIndicators.length > 0) {
        console.log('  ✓ Индикаторы ROS:');
        rosIndicators.forEach(ind => console.log(`    - ${ind}`));
      } else {
        console.log('  ⚠️  Прямых индикаторов ROS не найдено');
      }

      console.log('\n📊 ИТОГОВАЯ ИНФОРМАЦИЯ:');
      console.log('═'.repeat(60));
      console.log(`Система: ${sysInfo.sysDescr || 'N/A'}`);
      console.log(`Имя: ${sysInfo.sysName || 'N/A'}`);
      console.log(`Расположение: ${sysInfo.sysLocation || 'N/A'}`);
      console.log(`Uptime: ${sysInfo.sysUpTime || 'N/A'} тиков`);
      
      if (httpInfo) {
        console.log(`HTTP: Доступен (${httpInfo.status})`);
      }

    } catch (error) {
      console.error('Ошибка:', error.message);
    } finally {
      this.close();
    }
  }
}

// CLI
program
  .name('ros-discovery')
  .description('ROS Discovery Tool через сетевые протоколы')
  .version('1.0.0')
  .requiredOption('-i, --ip <address>', 'Target IP address')
  .option('-c, --community <string>', 'SNMP community', 'UTMC');

program.parse();

const options = program.opts();

async function main() {
  const discovery = new ROSDiscovery({
    ip: options.ip,
    community: options.community
  });
  
  await discovery.discover();
}

main().catch(console.error);
