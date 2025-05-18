#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <unistd.h>

#define PORT 8080
#define BUFFER_SIZE 1024  // **修改：接收 1024 字节数据**

int main() {
    // 创建监听套接字
    int listen_fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (listen_fd < 0) {
        perror("socket");
        exit(EXIT_FAILURE);
    }

    // 启用 MPTCP
    int enable = 1;
    setsockopt(listen_fd, SOL_TCP, 42, &enable, sizeof(enable));

    // 绑定端口
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(PORT);
    addr.sin_addr.s_addr = INADDR_ANY; // 监听所有接口

    if (bind(listen_fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        perror("bind");
        exit(EXIT_FAILURE);
    }

    // 开始监听
    if (listen(listen_fd, 5) < 0) {
        perror("listen");
        exit(EXIT_FAILURE);
    }

    printf("MPTCP Echo Server listening on port %d...\n", PORT);

    while (1) {
        // 接受客户端连接
        struct sockaddr_in client_addr;
        socklen_t client_len = sizeof(client_addr);
        int client_fd = accept(listen_fd, (struct sockaddr*)&client_addr, &client_len);
        if (client_fd < 0) {
            perror("accept");
            continue;
        }

        // 打印客户端信息
        char client_ip[INET_ADDRSTRLEN];
        inet_ntop(AF_INET, &client_addr.sin_addr, client_ip, INET_ADDRSTRLEN);
        printf("New connection from %s:%d\n", client_ip, ntohs(client_addr.sin_port));

        // **优化：大 buffer 处理**
        char buffer[BUFFER_SIZE];
        ssize_t bytes_read;
        int total_received = 0;

        while ((bytes_read = recv(client_fd, buffer, BUFFER_SIZE, 0)) > 0) {
            total_received += bytes_read;

            // **减少 printf 频率**
            if (total_received % (BUFFER_SIZE * 1000) == 0) {
                printf("Received %d KB data from %s\n", total_received / 1024, client_ip);
            }

            // 直接回显数据
            if (send(client_fd, buffer, bytes_read, 0) != bytes_read) {
                perror("send");
                break;
            }
        }

        if (bytes_read < 0) {
            perror("recv");
        }

        printf("Connection closed by %s:%d\n", client_ip, ntohs(client_addr.sin_port));
        close(client_fd);
    }

    close(listen_fd);
    return 0;
}
