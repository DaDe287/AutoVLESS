clear

# Enable BBR
sudo modprobe tcp_bbr
echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Firewall
curl -fsSL https://raw.githubusercontent.com/DaDe287/AutoVLESS/refs/heads/main/setup-firewall.sh | sudo bash

# 3x-ui
curl -fsSL https://raw.githubusercontent.com/DaDe287/AutoVLESS/refs/heads/main/install-panel-and-xray.sh | sudo bash
