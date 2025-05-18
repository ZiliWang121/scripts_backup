#!/usr/bin/env python3
"""
Server 端脚本：
- 精确接收每块数据（默认 1024 字节）
- 从每块中解析出发送时间戳，计算 application delay
- 记录 application goodput（累计收多少字节 / 总耗时）
- 记录 download time（整个传输时间）
适用于 ReLeS 所使用的 “文件下载” 场景。
"""

import socket
import struct
import time
import csv

# ------------------- 配置区域 -------------------
LISTEN_IP = "0.0.0.0"          # Server 对外监听地址（全接口）
LISTEN_PORT = 8888             # 与 UE 保持一致
CHUNK_SIZE = 1024              # 每块大小（单位：字节），前8字节是 timestamp
TOTAL_CHUNKS = None            # 若为 None 则自动直到 EOF；也可设置固定值
CSV_FILE = "recv_log.csv"      # 输出 CSV 日志
# ------------------------------------------------


def recv_exact(sock, size):
    """
    精确接收 size 字节的数据。
    如果中间断开连接或异常返回，将 raise。
    """
    buf = b''
    while len(buf) < size:
        chunk = sock.recv(size - len(buf))
        if not chunk:
            raise ConnectionError("连接断开，提前结束")
        buf += chunk
    return buf


# 创建 TCP socket
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
sock.bind((LISTEN_IP, LISTEN_PORT))
sock.listen(1)

print(f"[Server] Listening on {LISTEN_IP}:{LISTEN_PORT} ...")
conn, addr = sock.accept()
print(f"[Server] Connection from {addr}")

# 打开 CSV 文件用于记录日志
csvfile = open(CSV_FILE, "w", newline='')
csvwriter = csv.writer(csvfile)
csvwriter.writerow(["Packet#", "Delay(ms)", "Goodput(KB/s)", "RecvTime(s)"])

# 初始化计数器
recv_count = 0
recv_bytes = 0
start_time = time.time()

try:
    while True:
        try:
            # 精确接收一块完整数据（含时间戳）
            data = recv_exact(conn, CHUNK_SIZE)
        except ConnectionError:
            print("[Server] Connection closed by client.")
            break

        recv_time = time.time()  # 当前完整块收完的时间戳

        # 提取前8字节为发送时间戳（big-endian float64）
        try:
            send_ts = struct.unpack("!d", data[:8])[0]
        except struct.error:
            print(f"[WARN] 数据块 #{recv_count+1} 解码失败，跳过")
            continue

        delay_ms = (recv_time - send_ts) * 1000  # 单位：毫秒

        # 更新统计值
        recv_count += 1
        recv_bytes += len(data)
        duration = recv_time - start_time
        goodput_kbps = (recv_bytes / 1024) / duration if duration > 0 else 0

        # 打印和写入日志
        print(f"[Recv] #{recv_count} | Delay = {delay_ms:.2f} ms | Goodput = {goodput_kbps:.2f} KB/s")
        csvwriter.writerow([recv_count, delay_ms, goodput_kbps, recv_time])

        # 如果设置了 TOTAL_CHUNKS，可用于控制发送次数
        if TOTAL_CHUNKS is not None and recv_count >= TOTAL_CHUNKS:
            break

finally:
    # 结束统计并关闭连接
    end_time = time.time()
    conn.close()
    sock.close()
    csvfile.close()

    total_time = end_time - start_time
    print(f"[Done] Total download time: {total_time:.2f} s")
