#!/usr/bin/env python3
"""
SNMP Agent Emulator для виртуального контроллера SINTEZ UTMC
Эмулирует SNMP агент контроллера на основе реальной конфигурации
"""

import json
import time
import threading
from datetime import datetime
from typing import Dict, Optional, Tuple
from pysnmp.hlapi import *

# OID константы
UTMC_BASE = "1.3.6.1.4.1.13267"
UTC_TYPE2_OPERATION_MODE = f"{UTMC_BASE}.3.2.4.1"
UTC_CONTROL_ENTRY = f"{UTMC_BASE}.3.2.4.2.1"
UTC_CONTROL_FN = f"{UTC_CONTROL_ENTRY}.5"
UTC_CONTROL_LO = f"{UTC_CONTROL_ENTRY}.11"
UTC_CONTROL_FF = f"{UTC_CONTROL_ENTRY}.20"
UTC_REPLY_ENTRY = f"{UTMC_BASE}.3.2.5.1.1"
UTC_REPLY_GN = f"{UTC_REPLY_ENTRY}.3"
UTC_REPLY_STAGE_LENGTH = f"{UTC_REPLY_ENTRY}.4"
UTC_REPLY_STAGE_COUNTER = f"{UTC_REPLY_ENTRY}.5"
UTC_REPLY_TRANSITION = f"{UTC_REPLY_ENTRY}.7"
UTC_REPLY_FR = f"{UTC_REPLY_ENTRY}.36"

class VirtualController:
    """Виртуальный контроллер SINTEZ UTMC"""
    
    def __init__(self, config_path: str = None):
        # Состояние контроллера
        self.operation_mode = 1  # 0=Local, 1=Standalone, 2=Monitor, 3=UTC Control
        self.current_phase = 0  # 0=нет фазы, 1-7=номер фазы
        self.stage_length = 20  # Длительность фазы (секунды)
        self.stage_counter = 0  # Счётчик текущей фазы (секунды)
        self.stage_start_time = time.time()  # Время начала текущей фазы
        self.transition = 0  # Переходные процессы (0=нет, 1=есть)
        self.flashing_mode = 0  # Режим мигания (0=нет, 1=активно)
        self.control_ff = 0  # Контроль мигания (0=выкл, 1=вкл)
        
        # Защита от ошибок мигания
        self.deny_remote_on_amber_error = True
        self.amber_flash_error = False
        
        # Специальные фазы (nominated stages)
        self.special_phases = [1, 2, 3, 4]
        
        # Минимальные периоды работы фаз
        self.min_phase_time = 5  # Минимальное время работы фазы (секунды)
        self.safe_time = 3  # Безопасное время (секунды)
        
        # Логирование
        self.log_file = "virtual_controller.log"
        self.log_operations = True
        
        # Загрузка конфигурации
        if config_path:
            self.load_config(config_path)
        
        # Запуск обновления состояния
        self.running = True
        self.update_thread = threading.Thread(target=self.update_state_loop, daemon=True)
        self.update_thread.start()
        
        self.log("Virtual Controller initialized")
    
    def load_config(self, config_path: str):
        """Загрузка конфигурации из файла"""
        try:
            with open(config_path, 'r') as f:
                config = json.load(f)
            
            # Загрузка режима работы
            mode_str = config.get('mode', 'local')
            mode_map = {'local': 0, 'standalone': 1, 'monitor': 2, 'remote': 3, 'utc': 3}
            self.operation_mode = mode_map.get(mode_str.lower(), 1)
            
            # Загрузка параметров фаз
            programm = config.get('programm', {})
            phases = programm.get('phases', {})
            self.special_phases = phases.get('specialPhases', [1, 2, 3, 4])
            
            plans = programm.get('plans', {})
            if plans:
                plan1 = plans.get('1', {})
                actions = plan1.get('actions', [])
                if actions:
                    # Используем параметры первой фазы
                    first_action = actions[0]
                    self.min_phase_time = first_action.get('min_time', 5)
                    self.safe_time = first_action.get('safe_time', 3)
                    self.stage_length = first_action.get('fix_time', 20)
            
            self.log(f"Configuration loaded from {config_path}")
            self.log(f"Mode: {mode_str} ({self.operation_mode})")
            self.log(f"Special phases: {self.special_phases}")
            self.log(f"Min phase time: {self.min_phase_time} sec")
            
        except Exception as e:
            self.log(f"Error loading config: {e}")
    
    def update_state_loop(self):
        """Цикл обновления состояния контроллера"""
        while self.running:
            # Обновление счётчика фазы
            if self.current_phase > 0:
                elapsed = time.time() - self.stage_start_time
                self.stage_counter = int(elapsed)
                
                # Автоматический переход на следующую фазу (для эмуляции)
                if self.stage_counter >= self.stage_length:
                    # Переход на следующую фазу (циклически)
                    self.current_phase = (self.current_phase % 7) + 1
                    self.stage_start_time = time.time()
                    self.stage_counter = 0
                    self.transition = 1
                    self.log(f"Phase transition: new phase = {self.current_phase}")
                    time.sleep(1)  # Переход длится 1 секунду
                    self.transition = 0
            
            time.sleep(0.5)  # Обновление каждые 0.5 секунды
    
    def log(self, message: str):
        """Логирование операций"""
        if self.log_operations:
            timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            log_msg = f"[{timestamp}] {message}"
            print(log_msg)
            try:
                with open(self.log_file, 'a') as f:
                    f.write(log_msg + '\n')
            except:
                pass
    
    def get_oid_value(self, oid: str) -> Optional[Tuple[int, any]]:
        """Получение значения OID"""
        # Типы: 2=Integer, 4=OctetString
        
        if oid == UTC_TYPE2_OPERATION_MODE:
            return (2, self.operation_mode)
        
        elif oid == UTC_REPLY_GN:
            # Текущая фаза как битовая маска (OctetString)
            if self.current_phase > 0:
                phase_mask = 1 << (self.current_phase - 1)
                return (4, bytes([phase_mask]))
            else:
                return (4, bytes([0]))
        
        elif oid == UTC_REPLY_STAGE_LENGTH:
            return (2, self.stage_length)
        
        elif oid == UTC_REPLY_STAGE_COUNTER:
            return (2, self.stage_counter)
        
        elif oid == UTC_REPLY_TRANSITION:
            return (2, self.transition)
        
        elif oid == UTC_REPLY_FR:
            return (2, self.flashing_mode)
        
        return None
    
    def set_oid_value(self, oid: str, value: any) -> bool:
        """Установка значения OID"""
        success = False
        
        if oid == UTC_TYPE2_OPERATION_MODE:
            new_mode = int(value)
            if 0 <= new_mode <= 3:
                old_mode = self.operation_mode
                self.operation_mode = new_mode
                self.log(f"Operation mode changed: {old_mode} -> {new_mode}")
                success = True
        
        elif oid == UTC_CONTROL_FN:
            # Установка фазы (OctetString - битовая маска)
            if isinstance(value, bytes) and len(value) > 0:
                phase_mask = value[0]
                # Определение номера фазы из битовой маски
                for i in range(8):
                    if phase_mask & (1 << i):
                        new_phase = i + 1
                        if new_phase != self.current_phase:
                            self.current_phase = new_phase
                            self.stage_start_time = time.time()
                            self.stage_counter = 0
                            self.transition = 1
                            self.log(f"Phase set: {new_phase} (mask=0x{phase_mask:02x})")
                            time.sleep(0.5)  # Переход
                            self.transition = 0
                        success = True
                        break
        
        elif oid == UTC_CONTROL_FF:
            # Управление миганием
            new_ff = int(value)
            
            # Проверка защиты от ошибок мигания
            if self.deny_remote_on_amber_error and self.amber_flash_error:
                if self.operation_mode != 3:
                    self.log("WARNING: Remote control denied due to amber flash error protection")
                    return False
            
            # Проверка режима работы
            if new_ff == 1 and self.operation_mode != 3:
                self.log(f"WARNING: Flash control requires UTC Control mode (current: {self.operation_mode})")
                # Автоматически переводим в режим UTC Control
                self.operation_mode = 3
                self.log("Auto-switched to UTC Control mode")
            
            # Проверка специальной фазы (nominated stage)
            if new_ff == 1 and self.current_phase not in self.special_phases:
                self.log(f"WARNING: Flash control requires special phase (current: {self.current_phase}, special: {self.special_phases})")
                # Автоматически устанавливаем специальную фазу (фаза 1)
                self.current_phase = 1
                self.stage_start_time = time.time()
                self.stage_counter = 0
                self.log("Auto-set to special phase 1")
            
            # Проверка минимального периода работы фазы
            if new_ff == 1 and self.stage_counter < self.min_phase_time:
                wait_time = self.min_phase_time - self.stage_counter + self.safe_time
                self.log(f"WARNING: Minimum phase time not expired (counter: {self.stage_counter}, min: {self.min_phase_time})")
                self.log(f"Waiting {wait_time} seconds for minimum period...")
                time.sleep(wait_time)
                self.stage_counter = self.min_phase_time + self.safe_time
            
            self.control_ff = new_ff
            
            # Активация мигания (с задержкой для эмуляции)
            if new_ff == 1:
                self.log("Flash control activated (utcControlFF=1)")
                # Эмуляция задержки активации мигания
                time.sleep(2)
                self.flashing_mode = 1
                self.log("Flashing mode activated (utcReplyFR=1)")
            else:
                self.log("Flash control deactivated (utcControlFF=0)")
                self.flashing_mode = 0
                self.log("Flashing mode deactivated (utcReplyFR=0)")
            
            success = True
        
        elif oid == UTC_CONTROL_LO:
            # Управление лампами (Lamps On/Off)
            self.log(f"Lamps control: {int(value)}")
            success = True
        
        return success
    
    def get_status(self) -> Dict:
        """Получение текущего статуса контроллера"""
        return {
            'operation_mode': self.operation_mode,
            'current_phase': self.current_phase,
            'stage_length': self.stage_length,
            'stage_counter': self.stage_counter,
            'transition': self.transition,
            'flashing_mode': self.flashing_mode,
            'control_ff': self.control_ff,
            'special_phases': self.special_phases,
            'min_phase_time': self.min_phase_time
        }
    
    def print_status(self):
        """Вывод текущего статуса"""
        status = self.get_status()
        mode_names = {0: 'Local', 1: 'Standalone', 2: 'Monitor', 3: 'UTC Control'}
        print("\n" + "="*60)
        print("VIRTUAL CONTROLLER STATUS")
        print("="*60)
        print(f"Operation Mode: {status['operation_mode']} ({mode_names.get(status['operation_mode'], 'Unknown')})")
        print(f"Current Phase: {status['current_phase']} {'(SPECIAL)' if status['current_phase'] in status['special_phases'] else ''}")
        print(f"Stage Length: {status['stage_length']} sec")
        print(f"Stage Counter: {status['stage_counter']} sec")
        print(f"Transition: {status['transition']}")
        print(f"Flashing Mode (FR): {status['flashing_mode']} {'✓ ACTIVE' if status['flashing_mode'] == 1 else ''}")
        print(f"Control FF: {status['control_ff']}")
        print(f"Special Phases: {status['special_phases']}")
        print(f"Min Phase Time: {status['min_phase_time']} sec")
        print("="*60 + "\n")

def snmp_get_handler(oid: str, controller: VirtualController) -> Optional[Tuple[int, any]]:
    """Обработчик SNMP GET запросов"""
    return controller.get_oid_value(oid)

def snmp_set_handler(oid: str, value: any, controller: VirtualController) -> bool:
    """Обработчик SNMP SET запросов"""
    return controller.set_oid_value(oid, value)

if __name__ == "__main__":
    import sys
    
    # Загрузка конфигурации из снэпшота (если доступна)
    config_path = None
    if len(sys.argv) > 1:
        config_path = sys.argv[1]
    else:
        # Попытка найти конфигурацию в снэпшоте
        import os
        snapshot_config = "/home/alexey/shared_vm/spectr_utmc/spectr_utmc/controller_snapshot/home/voicelink/rtc/resident/config"
        if os.path.exists(snapshot_config):
            config_path = snapshot_config
    
    # Создание виртуального контроллера
    controller = VirtualController(config_path)
    
    print("Virtual Controller SINTEZ UTMC")
    print("="*60)
    print("Press Ctrl+C to stop")
    print("="*60)
    
    # Вывод статуса каждые 5 секунд
    try:
        while True:
            controller.print_status()
            time.sleep(5)
    except KeyboardInterrupt:
        print("\nStopping virtual controller...")
        controller.running = False
