#!/bin/bash

# Check for root
if [[ $EUID -ne 0 ]]; then
    echo "Error: run as root (sudo bash enable_bbr.sh)"
    exit 1
fi

# Check if BBR is already enabled
if [[ $(sysctl -n net.ipv4.tcp_congestion_control) == "bbr" ]] && [[ $(sysctl -n net.core.default_qdisc) =~ ^(fq|cake)$ ]]; then
    echo "BBR is already enabled!"
    sysctl net.ipv4.tcp_congestion_control
    sysctl net.core.default_qdisc
    exit 0
fi

# Load BBR kernel module
modprobe tcp_bbr

# Write to sysctl.d (preferred over sysctl.conf)
cat > /etc/sysctl.d/99-bbr.conf << EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

# Apply
sysctl --system > /dev/null 2>&1

# Verify
CC=$(sysctl -n net.ipv4.tcp_congestion_control)
QD=$(sysctl -n net.core.default_qdisc)

if [[ "$CC" == "bbr" ]]; then
    echo "BBR enabled successfully!"
    echo "  congestion_control = $CC"
    echo "  default_qdisc      = $QD"
else
    echo "Failed to enable BBR. Check your kernel version (need 4.9+)."
    echo "  kernel: $(uname -r)"
    exit 1
fi
