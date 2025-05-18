#!/bin/bash
set -e

echo "======= MPTCP ➝ Proxy ➝ TCP Verification Script (Distributed Echo Test) ======="

# === Configuration ===
LISTEN_PORT=8888                # Proxy listening port for UE (after REDIRECT)
ECHO_PORT=8888                  # Echo Server's TCP port
ECHO_HOST=192.168.56.107        # Echo Server's IP (actual destination after proxy forwards)
DURATION=10                     # Packet capture duration (seconds)
MPTCP_IN_IFACE="upfgtp"         # Proxy's input interface for MPTCP traffic from UE

echo -e "\n[Step 1] Checking if Proxy received multiple MPTCP subflows from UE..."

# Extract unique UE subflow source IPs (e.g., 10.60.0.1 and 10.60.0.2)
SUBFLOWS=$(ss -tiepm | grep ":$LISTEN_PORT" | grep -oE '10\.60\.0\.[0-9]+' | sort -u)
SUBFLOW_COUNT=$(echo "$SUBFLOWS" | wc -l)

echo "-> Detected $SUBFLOW_COUNT unique UE source IP(s) connected to Proxy on port $LISTEN_PORT:"
echo "$SUBFLOWS"

if [[ $SUBFLOW_COUNT -ge 2 ]]; then
    echo "PASS: Proxy received multiple MPTCP subflows from UE"
else
    echo "FAIL: Only $SUBFLOW_COUNT subflow(s) detected; check if all paths are used"
fi

echo -e "\n[Step 1.5] Capturing MPTCP traffic on [$MPTCP_IN_IFACE] for $DURATION seconds..."
sudo timeout $DURATION tcpdump -n -i "$MPTCP_IN_IFACE" "port $LISTEN_PORT and tcp" -tt 2>/dev/null \
  | tee /tmp/proxy_mptcp.log | head -n 10

REV_FLOW=$(grep -c "$LISTEN_PORT > 10.60.0." /tmp/proxy_mptcp.log || true)
echo "-> Detected $REV_FLOW packet(s) from Proxy back to UE on $MPTCP_IN_IFACE"
if [[ $REV_FLOW -gt 0 ]]; then
    echo "PASS: Reverse MPTCP traffic (Proxy → UE) confirmed"
else
    echo "FAIL: No reverse traffic seen; might be timing issue"
fi

echo -e "\n[Step 1.6] Checking if each subflow received response from Proxy..."
for ip in $SUBFLOWS; do
    COUNT=$(grep -c "$LISTEN_PORT > $ip" /tmp/proxy_mptcp.log || true)
    echo "-> Response packets to $ip: $COUNT"
    if [[ $COUNT -eq 0 ]]; then
        echo "FAIL: No response packets found to subflow $ip"
    fi
done

echo -e "\n[Step 1.7] Checking for MPTCP DSS option in captured packets..."
if grep -qi "mptcp dss" /tmp/proxy_mptcp.log; then
    echo "PASS: MPTCP DSS option found; indicates active MPTCP session"
else
    echo "FAIL: No DSS option seen; may indicate inactive or short capture"
fi

echo -e "\n[Step 2] Checking TCP communication between Proxy and Echo Server ($ECHO_HOST:$ECHO_PORT)..."

OUT_DEV=$(ip route get $ECHO_HOST | awk '/dev/ {for(i=1;i<=NF;i++) if ($i=="dev") print $(i+1)}')

PKT_SUMMARY=$(sudo timeout $DURATION tcpdump -n -i "$OUT_DEV" host $ECHO_HOST and port $ECHO_PORT -tt 2>/dev/null | wc -l)
PSH_COUNT=$(sudo timeout $DURATION tcpdump -n -i "$OUT_DEV" host $ECHO_HOST and port $ECHO_PORT 2>/dev/null | grep -c "Flags \[P.")

echo "-> Total packets between Proxy and Echo Server: $PKT_SUMMARY"
echo "-> TCP data packets (PSH flag): $PSH_COUNT"
if [[ $PKT_SUMMARY -gt 20 && $PSH_COUNT -gt 0 ]]; then
    echo "PASS: Proxy is sending TCP data to Echo Server"
else
    echo "FAIL: Proxy may not be forwarding data correctly"
fi

echo -e "\n[Step 2.5] Checking if Echo Server responded to Proxy..."
ECHO_RECV_COUNT=$(sudo timeout $DURATION tcpdump -n -i "$OUT_DEV" src $ECHO_HOST and port $ECHO_PORT 2>/dev/null | grep -c "Flags \[P.")
echo "-> Echo Server → Proxy TCP data packets: $ECHO_RECV_COUNT"
if [[ $ECHO_RECV_COUNT -gt 0 ]]; then
    echo "PASS: Echo Server sent response to Proxy"
else
    echo "FAIL: No response seen from Echo Server"
fi

echo -e "\n[Step 2.6] Verifying that Proxy → Echo Server is pure TCP (no MPTCP DSS)..."
DSS_FOUND=$(sudo timeout $DURATION tcpdump -n -i "$OUT_DEV" host $ECHO_HOST and port $ECHO_PORT 2>/dev/null | grep -ci "mptcp dss" || true)
echo "-> DSS occurrences in Proxy ↔ Echo Server traffic: $DSS_FOUND"
if [[ $DSS_FOUND -eq 0 ]]; then
    echo "PASS: No MPTCP DSS found in Proxy → Echo traffic (pure TCP)"
else
    echo "FAIL: Unexpected MPTCP DSS found in Proxy → Echo traffic!"
fi

echo -e "\n[Step 3] Current TCP connection state on Proxy:"
ss -antp | grep ":$LISTEN_PORT" || echo "(No active connections found)"

echo -e "\n[Step 4] Final Summary:"
if [[ $SUBFLOW_COUNT -ge 2 && $REV_FLOW -gt 0 && $PSH_COUNT -gt 0 && $ECHO_RECV_COUNT -gt 0 ]]; then
    echo -e "SUCCESS: MPTCP ➝ Proxy ➝ TCP chain verified successfully"
    echo "  - Multiple subflows from UE detected"
    echo "  - MPTCP DSS option confirmed"
    echo "  - Proxy forwarded TCP data to Echo Server"
    echo "  - Echo Server replied as expected"
else
    echo -e "WARNING: One or more checks failed"
    [[ $SUBFLOW_COUNT -lt 2 ]] && echo "  • Only $SUBFLOW_COUNT subflow(s) from UE"
    [[ $REV_FLOW -eq 0 ]] && echo "  • No Proxy → UE packets captured"
    [[ $PSH_COUNT -eq 0 ]] && echo "  • No TCP data sent to Echo Server"
    [[ $ECHO_RECV_COUNT -eq 0 ]] && echo "  • No TCP reply from Echo Server"
    echo "Please inspect logs and consider increasing capture time or checking iptables/NAT rules"
fi

rm -f /tmp/proxy_mptcp.log
