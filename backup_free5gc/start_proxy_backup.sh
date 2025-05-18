#!/bin/bash

echo "===================== 🧩 启动 MPTCP Transparent Proxy ====================="

PORT=8080  # 监听端口
UE_SUBNET="10.60.0.0/16"  # UE 使用的子网
PROXY_BIN=~/MPTCP-Proxy/mptcp-proxy  # 可执行文件路径

echo "🔧 启用 IP 绑定非本地地址..."
sudo sysctl -w net.ipv4.ip_nonlocal_bind=1

echo "🔧 设置 iptables：将目标为 80 端口的连接 REDIRECT 到本地 $PORT..."
sudo iptables -t nat -A PREROUTING -s $UE_SUBNET -p tcp --dport 80 -j REDIRECT --to-port $PORT

echo "🔧 启动 Transparent Proxy..."
sudo $PROXY_BIN --mode server --port $PORT --transparent &

sleep 1
echo "✅ Transparent Proxy 已启动并监听 $PORT 端口（用于 MPTCP ➝ TCP 转发）"
