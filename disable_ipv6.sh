# Disable Ipv6
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
sudo sysctl -w net.ipv6.conf.lo.disable_ipv6=1

# Disable Ipv6
echo "net.ipv6.conf.all.disable_ipv6 = 1" > /etc/sysctl.conf
echo "net.ipv6.conf.default.disable_ipv6 = 1" > /etc/sysctl.conf
echo "net.ipv6.conf.lo.disable_ipv6 = 1" > /etc/sysctl.conf

# Commit changes and reboot
sudo sysctl -p
sudo reboot
