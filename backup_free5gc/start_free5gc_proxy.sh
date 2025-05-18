#!/bin/bash

echo "===================== 🚀 启动 Free5GC + Transparent Proxy ====================="

echo "🔧 启用 IP 转发..."
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf

echo "🔧 启用本地地址 redirect 支持（透明代理必需）..."
sudo sysctl -w net.ipv4.conf.all.route_localnet=1
echo "net.ipv4.conf.all.route_localnet=1" | sudo tee -a /etc/sysctl.conf

echo "🔧 设置 UPF 出口 NAT（eth0 出公网）..."
sudo iptables -t nat -C POSTROUTING -o eth0 -j MASQUERADE 2>/dev/null || \
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

echo "🔧 设置 TCP MSS 避免分片..."
sudo iptables -C FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1400 2>/dev/null || \
sudo iptables -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1400

echo "🔧 允许 FORWARD..."
sudo iptables -C FORWARD -j ACCEPT 2>/dev/null || \
sudo iptables -I FORWARD 1 -j ACCEPT

echo "🔧 清理旧的 NAT 到 proxy 虚拟机的规则（已废弃）..."
sudo iptables -t nat -D POSTROUTING -s 10.60.0.0/16 -d 192.168.56.106 -j MASQUERADE 2>/dev/null || true

echo "🔧 配置 Transparent Proxy：将发往公网80端口的 TCP 流量 REDIRECT 给本地 proxy..."
sudo iptables -t nat -C PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8080 2>/dev/null || \
sudo iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8080

echo "🔧 加载常见 MPTCP 模块..."
for mod in mptcp_balia mptcp_olia mptcp_rr mptcp_wvegas mptcp_netlink; do
    sudo modprobe $mod 2>/dev/null || true
done

echo "🔧 设置 MPTCP 参数..."
sudo sysctl -w net.mptcp.mptcp_enabled=1
sudo sysctl -w net.mptcp.mptcp_path_manager=fullmesh
sudo sysctl -w net.mptcp.mptcp_scheduler=roundrobin
sudo sysctl -w net.ipv4.tcp_congestion_control=olia

echo "🚀 启动 Transparent Proxy（监听 8080）..."
#sudo LOG_LEVEL=debug ./proxy --mode server --port 8080 --transparent &

sleep 2

echo "🔧 检查 MongoDB 服务状态..."
sudo systemctl status mongod | grep "Active:"

echo "📡 启动 Free5GC 核心网组件..."
cd ~/free5gc
./run.sh &

sleep 2

echo "📡 启动 N3IWF（Wi-Fi 接入点）..."
sudo ./bin/n3iwf &

sleep 2

echo "🌐 启动 WebConsole (http://192.168.56.101:5000)..."
cd ~/free5gc/webconsole
./bin/webconsole &

echo "✅ 启动完成！Free5GC + Transparent Proxy 已准备就绪！"
