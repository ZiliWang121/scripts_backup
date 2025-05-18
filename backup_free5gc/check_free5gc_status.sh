#用于验证透明代理情况下free5gc状态的
#!/bin/bash
echo "🔍 检查 Free5GC 网络状态"

echo -e "\n📌 当前默认路由："
ip route | grep default

echo -e "\n📌 是否启用了 route_localnet："
sysctl net.ipv4.conf.all.route_localnet

echo -e "\n📌 PREROUTING REDIRECT 规则（iptables）："
iptables -t nat -nvL PREROUTING | grep REDIRECT || echo "❌ 没有 REDIRECT 规则！"

echo -e "\n📌 POSTROUTING MASQUERADE（eth1）是否存在："
iptables -t nat -nvL POSTROUTING | grep 'MASQUERADE' | grep 'eth1' || echo "❌ 没有 MASQUERADE 规则！"

echo -e "\n📌 到公网的路由跳转路径（example.com）："
ip route get 93.184.216.34

echo -e "\n📌 抓包（后台可同时执行）："
echo "sudo tcpdump -i any port 8080 -nn"
