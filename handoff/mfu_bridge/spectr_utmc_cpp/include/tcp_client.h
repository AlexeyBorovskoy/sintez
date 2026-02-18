#ifndef TCP_CLIENT_H
#define TCP_CLIENT_H

#include <string>
#include <functional>
#include <thread>
#include <atomic>
#include <mutex>
#include <queue>

class TcpClient {
public:
    using DataCallback = std::function<void(const std::string&)>;
    using ErrorCallback = std::function<void(const std::string&)>;
    
    TcpClient(const std::string& host, uint16_t port, int reconnectTimeout = 10);
    ~TcpClient();
    
    // Запуск клиента
    bool start();
    
    // Остановка клиента
    void stop();
    
    // Отправка данных
    bool send(const std::string& data);
    
    // Установка callback для получения данных
    void setDataCallback(DataCallback callback);
    
    // Установка callback для ошибок
    void setErrorCallback(ErrorCallback callback);
    
    // Проверка подключения
    bool isConnected() const;
    
    // Получение адреса сервера
    std::string getAddress() const;

private:
    std::string host_;
    uint16_t port_;
    int reconnectTimeout_;
    
    std::atomic<bool> running_;
    std::atomic<bool> connected_;
    std::thread workerThread_;
    
    DataCallback dataCallback_;
    ErrorCallback errorCallback_;
    
    std::mutex sendMutex_;
    std::queue<std::string> sendQueue_;
    
    int socketFd_;
    
    void workerThread();
    void connectToHost();
    void disconnect();
    void processData(const std::string& data);
    void processError(const std::string& error);
};

#endif // TCP_CLIENT_H
