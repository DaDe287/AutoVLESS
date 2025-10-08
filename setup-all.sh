clear
echo "y" | sudo apt update && apt upgrade -y

bash <(curl -Ls https://raw.githubusercontent.com/DaDe287/AutoVLESS/main/install-panel-and-xray.sh)

bash <(curl -Ls https://raw.githubusercontent.com/DaDe287/AutoVLESS/main/auto-panel-ssl.sh)

x-ui restart

bash <(curl -Ls https://raw.githubusercontent.com/DaDe287/AutoVLESS/main/setup-firewall.sh)

x-ui restart

# --- ВЫВОД ДАННЫХ 3x-ui В JSON ---
echo ""
echo "======================================="
echo " Получение данных панели 3x-ui..."
echo "======================================="

# Получаем IP и порт панели
PANEL_IP=$(hostname -I | awk '{print $1}')
PANEL_PORT=$(x-ui status 2>/dev/null | grep -oE ':[0-9]+' | head -1 | tr -d ':')

# Если порт не найден, используем дефолтный 2053
[ -z "$PANEL_PORT" ] && PANEL_PORT="2053"

# Получаем логин и пароль admin
XUI_INFO=$(x-ui list | grep admin | head -1)
USERNAME=$(echo "$XUI_INFO" | awk '{print $2}')
PASSWORD=$(echo "$XUI_INFO" | awk '{print $3}')

# Подстраховка на случай пустых данных
[ -z "$USERNAME" ] && USERNAME="admin"
[ -z "$PASSWORD" ] && PASSWORD="(не найден)"

API_URL="http://${PANEL_IP}:${PANEL_PORT}"

# Вывод в JSON
echo ""
echo "Данные панели 3x-ui:"
echo "{\"apiUrl\": \"${API_URL}\", \"username\": \"${USERNAME}\", \"password\": \"${PASSWORD}\"}"
echo ""
