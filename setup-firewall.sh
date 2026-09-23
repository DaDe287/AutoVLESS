# UFW
## Common Firewall rules
echo "Y" | sudo apt install ufw

ufw --force reset
ufw default deny incoming
ufw default allow outgoing
for p in 22 80 443 8443 5506 2096; do ufw allow $p/tcp; done
ufw --force enable

# IPTABLES 
## Block Torrents trafic
echo "Y" | sudo apt install iptables
iptables -A FORWARD -p tcp --dport 6881:6999 -j DROP
iptables -A FORWARD -p udp --dport 6881:6999 -j DROP

# Trafic-Guard
## Block Any scanners to the server
curl -fsSL https://raw.githubusercontent.com/DaDe287/Traffic-Guard/refs/heads/main/install.sh | sudo bash
