#!/bin/bash

# ===================== Deprecated Script =====================
# This script uses iptables REDIRECT to enable transparent proxy mode.
# It was the original setup used in the early stage of the testbed.
# Later replaced by a TPROXY-based solution for better control over
# destination addresses and support for multiple MPTCP subflows.
# =============================================================

echo "=====================   Starting MPTCP Transparent Proxy   ====================="

PORT=8080
UE_SUBNET="10.60.0.0/16"
TARGET_PORT=8888

echo "Enabling IP non-local bind..."
sudo sysctl -w net.ipv4.ip_nonlocal_bind=1

echo "Redirecting UE traffic to port $TARGET_PORT to proxy port $PORT..."
sudo iptables -t nat -A PREROUTING -s $UE_SUBNET -p tcp --dport $TARGET_PORT -j REDIRECT --to-port $PORT

echo "Starting proxy..."
sudo ./mptcp-proxy --mode server --port $PORT --transparent &
