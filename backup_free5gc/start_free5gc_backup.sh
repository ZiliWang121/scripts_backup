#!/bin/bash

echo "===================== 🚀 启动 Free5GC 服务器 ====================="

echo "🔧 启用 IP 转发..."
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf

echo "🔧 配置 UPF NAT（出口 eth0）..."
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

echo "🔧 设置 TCP MSS..."
sudo iptables -A FORWARD -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1400

echo "🔧 关闭防火墙 (UFW)..."
sudo systemctl stop ufw
sudo systemctl disable ufw

echo "🔧 确保 iptables FORWARD 链允许流量通过..."
sudo iptables -I FORWARD 1 -j ACCEPT

echo "🔧 确保 UE 可以访问 Proxy（5G & Wi-Fi）..."
sudo iptables -t nat -A POSTROUTING -s 10.60.0.0/16 -d 192.168.56.106 -j MASQUERADE

echo "🔧 检查 MongoDB 服务状态..."
sudo systemctl status mongod | grep "Active:"

echo "===================== ✅ 配置完成，启动 Free5GC ====================="

echo "📡 启动 Free5GC 核心网..."
cd ~/free5gc
./run.sh &  # 终端1

sleep 2  # 等待核心网启动

echo "📡 启动 N3IWF..."
cd ~/free5gc
sudo ./bin/n3iwf &  # 终端2

sleep 2  # 等待 N3IWF 启动

echo "🌐 启动 WebConsole (访问地址: http://192.168.56.101:5000)..."
cd ~/free5gc/webconsole
./bin/webconsole &  # 终端3

echo "✅ Free5GC 核心网 + N3IWF + WebConsole 启动完成！"
