# UFW

# COMMON FIREWALL RULES
echo "Y" | sudo apt install ufw
sudo ufw allow 443/tcp
sudo ufw allow 8080/tcp
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 1024:65535/udp
sudo ufw allow 1024:65535/tcp
echo "y" | sudo ufw enable

# IPTABLES 

# Block Torrents trafic
echo "Y" | sudo apt install iptables
iptables -A FORWARD -p tcp --dport 6881:6999 -j DROP
iptables -A FORWARD -p udp --dport 6881:6999 -j DROP

# # Block Any scanners to the server
# sudo traffic-guard full \
#   -u https://raw.githubusercontent.com/shadow-netlab/traffic-guard-lists/refs/heads/main/public/antiscanner.list \
#   -u https://raw.githubusercontent.com/shadow-netlab/traffic-guard-lists/refs/heads/main/public/government_networks.list \
#   --enable-logging
