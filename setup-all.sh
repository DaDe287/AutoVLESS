clear
echo "y" | sudo apt update && apt upgrade -y

bash <(curl -Ls https://raw.githubusercontent.com/DaDe287/AutoVLESS/main/setup-firewall.sh)

bash <(curl -Ls https://raw.githubusercontent.com/DaDe287/AutoVLESS/main/install-panel-and-xray.sh)

bash <(curl -Ls https://raw.githubusercontent.com/DaDe287/AutoVLESS/main/auto-panel-ssl.sh)

echo "$13" | x-ui 

