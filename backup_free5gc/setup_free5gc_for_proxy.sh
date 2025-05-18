#透明代理情况下为了proxy能行free5gc要进行的配置
#!/bin/bash

set -e

echo "🔧 开启 IP 转发"
sysctl -w net.ipv4.ip_forward=1 > /dev/null
grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf

echo "🔧 加载 NAT 模块"
modprobe iptable_nat || true

echo "🔧 启用 route_localnet（支持 REDIRECT 非本地 IP）"
sysctl -w net.ipv4.conf.all.route_localnet=1 > /dev/null

echo "🔧 添加 NAT（让 UE 出网地址伪装成 Free5GC）"
iptables -t nat -C POSTROUTING -s 10.60.0.0/16 -o eth1 -j MASQUERADE 2>/dev/null || \
iptables -t nat -A POSTROUTING -s 10.60.0.0/16 -o eth1 -j MASQUERADE

echo "🔧 添加透明代理 REDIRECT（把 UE 的出站 TCP 转给 Proxy 监听）"
iptables -t nat -C PREROUTING -s 10.60.0.0/16 -p tcp -j REDIRECT --to-port 8080 2>/dev/null || \
iptables -t nat -A PREROUTING -s 10.60.0.0/16 -p tcp -j REDIRECT --to-port 8080

echo "🔧 设置默认路由通过 Proxy（eth1）"
ip route | grep -q '^default via 192.168.56.106' || {
    ip route del default || true
    ip route add default via 192.168.56.106 dev eth1
}

echo "✅ Free5GC 网络配置完成！"
