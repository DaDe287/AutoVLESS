sudo ufw allow 443/tcp
sudo ufw allow 8080/tcp
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 1024:65535/udp
sudo ufw allow 1024:65535/tcp
echo "y" | sudo ufw enable
