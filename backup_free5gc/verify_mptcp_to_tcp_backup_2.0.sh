# 曾经proxy在server那台虚拟机上
# 当时由于proxy和server在同一虚拟机上，所以验证mptcp转tcp的脚本
# 基于Echo 服务在本地 (127.0.0.1)
# 现在proxy移动到本虚拟机，而server留在那
# 本脚本应进行改动
#!/bin/bash
set -e

echo "======= MPTCP ➝ Proxy ➝ TCP Verification Script (Local Echo Test) ======="

LISTEN_PORT=8080
ECHO_PORT=8888
DURATION=10

### Step 1: Check if Proxy receives multiple MPTCP subflows (UE ➝ Proxy is MPTCP)
echo -e "\n[Step 1] Checking if Proxy receives multiple MPTCP subflow connections..."

SUBFLOWS=$(ss -tiepm | grep -A1 ":$LISTEN_PORT" | grep -Eo '10\.60\.0\.[0-9]+:[0-9]+' | sort -u)
SUBFLOW_COUNT=$(echo "$SUBFLOWS" | wc -l)

echo "Detected $SUBFLOW_COUNT unique subflow connections (source address: 10.60.0.X)"
if [[ $SUBFLOW_COUNT -ge 2 ]]; then
    echo "Proxy has received multiple MPTCP subflow connections (direction: UE ➝ Proxy)"
else
    echo "Warning: Only $SUBFLOW_COUNT subflow(s) detected via ss; may be affected by NAT or incomplete visibility, recommend packet capture for confirmation"
fi

### Step 1.5: Confirm subflows received by Proxy using tcpdump (including ACK + PSH)
echo -e "\n[Step 1.5] Capturing packets to confirm subflows received by Proxy (Proxy ⬅️ UE)..."
sudo timeout $DURATION tcpdump -n -i any "port $LISTEN_PORT and tcp" -tt 2>/dev/null \
  | awk '/10\.60\.0\.[0-9]+\.[0-9]+ > .*8080/ || /8080 > 10\.60\.0\.[0-9]+/' \
  | grep -E "Flags \[(P\.|\.|P\.)\]" \
  | tee /tmp/mptcp_tcpdump.log | head -n 10

REV_FLOW=$(grep -c "8080 > 10.60.0." /tmp/mptcp_tcpdump.log || true)
if [[ $REV_FLOW -gt 0 ]]; then
    echo "Confirmed reverse traffic from UE to Proxy; MPTCP is bidirectional"
else
    echo "Warning: No ACK/PSH packets from UE to Proxy observed; might be due to one-way traffic or capture delay"
fi

### Step 1.6: Check for MPTCP characteristics in connection (token, olia, etc.)
echo -e "\n[Step 1.6] Analyzing ss -tiepm output for MPTCP-specific fields (e.g., token/olia)..."
ss -tiepm | grep -A2 ":$LISTEN_PORT" | grep -Ei 'olia|cubic|token|subflows' \
  && echo "MPTCP-specific fields detected" \
  || echo "Warning: No clear DSS/MPTCP fields detected; may be limited by ss output or kernel version"

### Step 2: Confirm bidirectional TCP communication between Proxy and Echo service
# ------------------【已修改开始】------------------
# echo -e "\n[Step 2] Checking bidirectional data exchange between Proxy and Echo service (127.0.0.1:$ECHO_PORT)..."
# 原本假设 echo 服务在本地，现在应修改为远程地址：

ECHO_HOST=192.168.56.107   # ✨ 新增：指定 Echo 服务的远程地址
OUT_DEV=$(ip route get $ECHO_HOST | awk '/dev/ {for(i=1;i<=NF;i++) if ($i=="dev") print $(i+1)}')  # ✨ 新增：自动检测出口接口

echo -e "\n[Step 2] Checking bidirectional data exchange between Proxy and Echo service ($ECHO_HOST:$ECHO_PORT via $OUT_DEV)..."

PKT_SUMMARY=$(sudo timeout $DURATION tcpdump -n -tt -i "$OUT_DEV" host $ECHO_HOST and port $ECHO_PORT 2>/dev/null | wc -l)  # ✨ 修改接口为动态
PSH_COUNT=$(sudo timeout $DURATION tcpdump -n -i "$OUT_DEV" host $ECHO_HOST and port $ECHO_PORT 2>/dev/null | grep -c "Flags \[P.")  # ✨ 修改接口为动态

# ------------------【已修改结束】------------------

echo "Total TCP packets with Echo service: $PKT_SUMMARY"
echo "TCP data packets sent (PSH): $PSH_COUNT"

if [[ $PKT_SUMMARY -gt 20 && $PSH_COUNT -gt 0 ]]; then
    echo "TCP communication between Proxy and Echo service is working (bidirectional)"
else
    echo "Error: TCP communication with Echo service appears abnormal"
fi

### Step 3: Current TCP connection state
echo -e "\n[Step 3] Current TCP connection state (ss -antp):"
ss -antp | grep ":$LISTEN_PORT" || echo "(No active connections)"

### Step 4: Final verification summary
echo -e "\n[Step 4] Verification Summary:"
if [[ $SUBFLOW_COUNT -ge 2 && $REV_FLOW -gt 0 && $PKT_SUMMARY -gt 20 && $PSH_COUNT -gt 0 ]]; then
    echo "Validation PASSED: UE ➝ Proxy using MPTCP (bidirectional), Proxy ➝ Echo using TCP (bidirectional)"
else
    echo "Warning: One or more validation conditions not met; please ensure end-to-end connectivity and packet capture coverage"
fi

# Cleanup
rm -f /tmp/mptcp_tcpdump.log
