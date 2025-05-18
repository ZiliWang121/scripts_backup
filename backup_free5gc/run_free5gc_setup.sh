#用于透明代理情况下验证free5gc情况的
#!/bin/bash
set -e

echo "=== 🔧 配置 Free5GC 网络转发 & REDIRECT ==="
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.ipv4.conf.all.route_localnet=1
sudo modprobe iptable_nat || true

sudo iptables -t nat -C PREROUTING -s 10.60.0.0/16 -p tcp -j REDIRECT --to-port 8080 2>/dev/null || \
sudo iptables -t nat -A PREROUTING -s 10.60.0.0/16 -p tcp -j REDIRECT --to-port 8080

sudo iptables -t nat -C POSTROUTING -s 10.60.0.0/16 -o eth1 -j MASQUERADE 2>/dev/null || \
sudo iptables -t nat -A POSTROUTING -s 10.60.0.0/16 -o eth1 -j MASQUERADE

ip route | grep -q '^default via 192.168.56.106' || {
    sudo ip route del default || true
    sudo ip route add default via 192.168.56.106 dev eth1
}

echo "=== 🧪 Free5GC 开始抓包 REDIRECT ==="
sudo timeout 20 tcpdump -i any port 8080 -nn
