#include "tcp_client.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <cstring>
#include <iostream>
#include <chrono>
#include <thread>

TcpClient::TcpClient(const std::string& host, uint16_t port, int reconnectTimeout)
    : host_(host), port_(port), reconnectTimeout_(reconnectTimeout),
      running_(false), connected_(false), socketFd_(-1) {
}

TcpClient::~TcpClient() {
    stop();
}

bool TcpClient::start() {
    if (running_) {
        return false;
    }
    
    running_ = true;
    workerThread_ = std::thread(&TcpClient::workerThread, this);
    return true;
}

void TcpClient::stop() {
    if (!running_) {
        return;
    }
    
    running_ = false;
    disconnect();
    
    if (workerThread_.joinable()) {
        workerThread_.join();
    }
}

bool TcpClient::send(const std::string& data) {
    if (!connected_) {
        return false;
    }
    
    std::lock_guard<std::mutex> lock(sendMutex_);
    sendQueue_.push(data);
    return true;
}

void TcpClient::setDataCallback(DataCallback callback) {
    dataCallback_ = callback;
}

void TcpClient::setErrorCallback(ErrorCallback callback) {
    errorCallback_ = callback;
}

bool TcpClient::isConnected() const {
    return connected_;
}

std::string TcpClient::getAddress() const {
    return host_ + ":" + std::to_string(port_);
}

void TcpClient::workerThread() {
    while (running_) {
        if (!connected_) {
            connectToHost();
        }
        
        if (connected_) {
            fd_set readFds, writeFds;
            struct timeval timeout;
            
            FD_ZERO(&readFds);
            FD_ZERO(&writeFds);
            FD_SET(socketFd_, &readFds);
            
            if (!sendQueue_.empty()) {
                FD_SET(socketFd_, &writeFds);
            }
            
            timeout.tv_sec = 1;
            timeout.tv_usec = 0;
            
            int result = select(socketFd_ + 1, &readFds, &writeFds, nullptr, &timeout);
            
            if (result > 0) {
                if (FD_ISSET(socketFd_, &readFds)) {
                    char buffer[4096];
                    ssize_t bytesRead = ::read(socketFd_, buffer, sizeof(buffer) - 1);
                    
                    if (bytesRead > 0) {
                        buffer[bytesRead] = '\0';
                        processData(std::string(buffer, bytesRead));
                    } else if (bytesRead == 0) {
                        // Соединение закрыто
                        disconnect();
                    } else {
                        // Ошибка чтения
                        processError("Read error: " + std::string(strerror(errno)));
                        disconnect();
                    }
                }
                
                if (FD_ISSET(socketFd_, &writeFds)) {
                    std::lock_guard<std::mutex> lock(sendMutex_);
                    if (!sendQueue_.empty()) {
                        std::string data = sendQueue_.front();
                        ssize_t bytesSent = ::write(socketFd_, data.c_str(), data.length());
                        
                        if (bytesSent > 0) {
                            sendQueue_.pop();
                        } else {
                            processError("Write error: " + std::string(strerror(errno)));
                            disconnect();
                        }
                    }
                }
            } else if (result < 0) {
                processError("Select error: " + std::string(strerror(errno)));
                disconnect();
            }
        } else {
            // Ожидание перед повторным подключением
            std::this_thread::sleep_for(std::chrono::seconds(reconnectTimeout_));
        }
    }
    
    disconnect();
}

void TcpClient::connectToHost() {
    if (connected_) {
        return;
    }
    
    socketFd_ = socket(AF_INET, SOCK_STREAM, 0);
    if (socketFd_ < 0) {
        processError("Socket creation failed: " + std::string(strerror(errno)));
        return;
    }
    
    // Установка неблокирующего режима
    int flags = fcntl(socketFd_, F_GETFL, 0);
    fcntl(socketFd_, F_SETFL, flags | O_NONBLOCK);
    
    struct sockaddr_in serverAddr;
    memset(&serverAddr, 0, sizeof(serverAddr));
    serverAddr.sin_family = AF_INET;
    serverAddr.sin_port = htons(port_);
    
    if (inet_pton(AF_INET, host_.c_str(), &serverAddr.sin_addr) <= 0) {
        // Попытка резолва DNS
        struct hostent* host = gethostbyname(host_.c_str());
        if (host == nullptr) {
            processError("Failed to resolve host: " + host_);
            close(socketFd_);
            socketFd_ = -1;
            return;
        }
        memcpy(&serverAddr.sin_addr, host->h_addr_list[0], host->h_length);
    }
    
    std::cout << "Connecting to " << getAddress() << std::endl;
    
    int result = connect(socketFd_, (struct sockaddr*)&serverAddr, sizeof(serverAddr));
    
    if (result < 0 && errno != EINPROGRESS) {
        processError("Connection failed: " + std::string(strerror(errno)));
        close(socketFd_);
        socketFd_ = -1;
        return;
    }
    
    // Проверка подключения
    fd_set writeFds;
    FD_ZERO(&writeFds);
    FD_SET(socketFd_, &writeFds);
    
    struct timeval timeout;
    timeout.tv_sec = 5;
    timeout.tv_usec = 0;
    
    result = select(socketFd_ + 1, nullptr, &writeFds, nullptr, &timeout);
    
    if (result > 0 && FD_ISSET(socketFd_, &writeFds)) {
        int error = 0;
        socklen_t len = sizeof(error);
        if (getsockopt(socketFd_, SOL_SOCKET, SO_ERROR, &error, &len) == 0 && error == 0) {
            connected_ = true;
            std::cout << "Connected to " << getAddress() << std::endl;
        } else {
            processError("Connection failed: " + std::string(strerror(error)));
            close(socketFd_);
            socketFd_ = -1;
        }
    } else {
        processError("Connection timeout");
        close(socketFd_);
        socketFd_ = -1;
    }
}

void TcpClient::disconnect() {
    if (connected_) {
        std::cout << getAddress() << " disconnected. Reconnect after " 
                  << reconnectTimeout_ << "s" << std::endl;
        connected_ = false;
    }
    
    if (socketFd_ >= 0) {
        close(socketFd_);
        socketFd_ = -1;
    }
}

void TcpClient::processData(const std::string& data) {
    if (dataCallback_) {
        dataCallback_(data);
    }
}

void TcpClient::processError(const std::string& error) {
    std::cerr << getAddress() << " error: " << error << std::endl;
    if (errorCallback_) {
        errorCallback_(error);
    }
}
