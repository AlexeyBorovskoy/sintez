#!/usr/bin/env python3
"""
Тестовый АСУДД сервер для проверки работы C++ моста
Имитирует работу реального АСУДД сервера, отправляя команды по протоколу Spectr-ITS
"""

import socket
import sys
import time
import threading
from datetime import datetime

class TestASUDDServer:
    def __init__(self, host='0.0.0.0', port=3000):
        self.host = host
        self.port = port
        self.socket = None
        self.clients = []
        self.running = False
        
    def calculate_checksum(self, data):
        """Вычисление checksum для протокола Spectr-ITS"""
        sum_val = 0
        for c in data:
            sum_val += ord(c)
            if sum_val & 0x100:
                sum_val += 1
            if sum_val & 0x80:
                sum_val += sum_val
                sum_val += 1
            else:
                sum_val += sum_val
            sum_val &= 0xFF
        return sum_val
    
    def format_command(self, command, request_id="TEST001"):
        """Форматирование команды в протокол Spectr-ITS"""
        time_str = datetime.now().strftime("%H:%M:%S")
        data = f"#{time_str} {command} {request_id}"
        checksum = self.calculate_checksum(data)
        return f"{data}${checksum:02x}\r"
    
    def handle_client(self, client_socket, address):
        """Обработка клиента"""
        print(f"[{datetime.now().strftime('%H:%M:%S')}] Клиент подключен: {address}")
        
        try:
            while self.running:
                # Чтение данных от клиента
                data = client_socket.recv(4096)
                if not data:
                    break
                
                message = data.decode('utf-8', errors='ignore')
                print(f"[{datetime.now().strftime('%H:%M:%S')}] Получено от клиента: {message.strip()}")
                
                # Обработка команд от клиента (если нужно)
                # В реальности клиент отправляет команды, а сервер их обрабатывает
                # Здесь мы просто логируем полученные данные
                    
        except Exception as e:
            print(f"[{datetime.now().strftime('%H:%M:%S')}] Ошибка при работе с клиентом {address}: {e}")
        finally:
            print(f"[{datetime.now().strftime('%H:%M:%S')}] Клиент отключен: {address}")
            client_socket.close()
            if client_socket in self.clients:
                self.clients.remove(client_socket)
    
    def send_command(self, command, request_id="TEST001"):
        """Отправка команды всем подключенным клиентам"""
        if not self.clients:
            print(f"[{datetime.now().strftime('%H:%M:%S')}] Нет подключенных клиентов")
            return False
        
        formatted_command = self.format_command(command, request_id)
        print(f"[{datetime.now().strftime('%H:%M:%S')}] Отправка команды: {formatted_command.strip()}")
        
        disconnected = []
        for client in self.clients:
            try:
                client.send(formatted_command.encode('utf-8'))
                print(f"[{datetime.now().strftime('%H:%M:%S')}] Команда отправлена клиенту")
            except Exception as e:
                print(f"[{datetime.now().strftime('%H:%M:%S')}] Ошибка отправки клиенту: {e}")
                disconnected.append(client)
        
        # Удаление отключенных клиентов
        for client in disconnected:
            if client in self.clients:
                self.clients.remove(client)
            client.close()
        
        return len(self.clients) > 0
    
    def interactive_mode(self):
        """Интерактивный режим для отправки команд"""
        print("")
        print("╔════════════════════════════════════════════════════════════╗")
        print("║  Интерактивный режим отправки команд                       ║")
        print("╚════════════════════════════════════════════════════════════╝")
        print("")
        print("Доступные команды:")
        print("  SET_YF [REQUEST_ID]     - Включить жёлтое мигание")
        print("  SET_PHASE <N> [REQUEST_ID] - Установить фазу N")
        print("  GET_STAT [REQUEST_ID]   - Получить статус")
        print("  SET_LOCAL [REQUEST_ID]  - Перевести в локальный режим")
        print("  quit                    - Выход")
        print("")
        
        while self.running:
            try:
                user_input = input("ASUDD> ").strip()
                if not user_input:
                    continue
                
                parts = user_input.split()
                cmd = parts[0].upper()
                
                if cmd == "QUIT" or cmd == "EXIT":
                    break
                elif cmd == "SET_YF":
                    request_id = parts[1] if len(parts) > 1 else f"TEST{int(time.time())}"
                    self.send_command("SET_YF", request_id)
                elif cmd == "SET_PHASE":
                    if len(parts) < 2:
                        print("Ошибка: укажите номер фазы")
                        continue
                    phase = parts[1]
                    request_id = parts[2] if len(parts) > 2 else f"TEST{int(time.time())}"
                    self.send_command(f"SET_PHASE {phase}", request_id)
                elif cmd == "GET_STAT":
                    request_id = parts[1] if len(parts) > 1 else f"TEST{int(time.time())}"
                    self.send_command("GET_STAT", request_id)
                elif cmd == "SET_LOCAL":
                    request_id = parts[1] if len(parts) > 1 else f"TEST{int(time.time())}"
                    self.send_command("SET_LOCAL", request_id)
                else:
                    print(f"Неизвестная команда: {cmd}")
                    
            except EOFError:
                break
            except KeyboardInterrupt:
                break
            except Exception as e:
                print(f"Ошибка: {e}")
    
    def start(self, interactive=False):
        """Запуск сервера"""
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        
        try:
            self.socket.bind((self.host, self.port))
            self.socket.listen(5)
            self.running = True
            
            print(f"╔════════════════════════════════════════════════════════════╗")
            print(f"║  Тестовый АСУДД сервер запущен                             ║")
            print(f"╚════════════════════════════════════════════════════════════╝")
            print(f"")
            print(f"Адрес: {self.host}:{self.port}")
            print(f"Ожидание подключений...")
            print(f"")
            
            # Запуск потока для приёма подключений
            accept_thread = threading.Thread(
                target=self._accept_connections,
                daemon=True
            )
            accept_thread.start()
            
            if interactive:
                # Интерактивный режим
                self.interactive_mode()
            else:
                # Ожидание завершения
                while self.running:
                    time.sleep(1)
                    
        except Exception as e:
            print(f"[{datetime.now().strftime('%H:%M:%S')}] Ошибка запуска сервера: {e}")
        finally:
            self.stop()
    
    def _accept_connections(self):
        """Поток для приёма подключений"""
        while self.running:
            try:
                self.socket.settimeout(1.0)
                client_socket, address = self.socket.accept()
                self.clients.append(client_socket)
                
                # Запуск потока для обработки клиента
                client_thread = threading.Thread(
                    target=self.handle_client,
                    args=(client_socket, address),
                    daemon=True
                )
                client_thread.start()
                
            except socket.timeout:
                continue
            except Exception as e:
                if self.running:
                    print(f"[{datetime.now().strftime('%H:%M:%S')}] Ошибка при принятии соединения: {e}")
    
    def stop(self):
        """Остановка сервера"""
        self.running = False
        if self.socket:
            self.socket.close()
        for client in self.clients:
            client.close()
        self.clients.clear()
        print(f"[{datetime.now().strftime('%H:%M:%S')}] Сервер остановлен")

def main():
    if len(sys.argv) < 2:
        print("Использование:")
        print(f"  {sys.argv[0]} start                    - Запустить сервер")
        print(f"  {sys.argv[0]} send SET_YF [REQUEST_ID] - Отправить команду SET_YF")
        print(f"  {sys.argv[0]} send SET_PHASE 1         - Отправить команду SET_PHASE")
        print(f"  {sys.argv[0]} send GET_STAT            - Отправить команду GET_STAT")
        print("")
        print("Примеры:")
        print(f"  {sys.argv[0]} start")
        print(f"  {sys.argv[0]} send SET_YF TEST001")
        sys.exit(1)
    
    command = sys.argv[1]
    
    if command == "start":
        interactive = "--interactive" in sys.argv or "-i" in sys.argv
        server = TestASUDDServer(host='0.0.0.0', port=3000)
        try:
            server.start(interactive=interactive)
        except KeyboardInterrupt:
            print("\nОстановка сервера...")
            server.stop()
    
    elif command == "send":
        if len(sys.argv) < 3:
            print("Ошибка: укажите команду для отправки")
            sys.exit(1)
        
        cmd = sys.argv[2]
        request_id = sys.argv[3] if len(sys.argv) > 3 else "TEST001"
        
        # Подключение к серверу (если он запущен)
        # В реальности команды отправляются сервером клиентам
        print("Для отправки команд используйте интерактивный режим сервера")
        print("Или подключитесь к серверу и отправьте команду вручную")
        print(f"Команда: {cmd}, Request ID: {request_id}")
    
    else:
        print(f"Неизвестная команда: {command}")
        sys.exit(1)

if __name__ == "__main__":
    main()
