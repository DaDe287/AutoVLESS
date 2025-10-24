clear
echo "y" | sudo apt update && apt upgrade -y

# --- УСТАНОВКА 3x-ui с перехватом вывода ---
INSTALL_OUTPUT=$(bash <(curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh) 2>&1)

# Сразу выводим оригинальный лог пользователю
echo "$INSTALL_OUTPUT"

bash <(curl -Ls https://raw.githubusercontent.com/DaDe287/AutoVLESS/main/auto-panel-ssl.sh)

x-ui restart

bash <(curl -Ls https://raw.githubusercontent.com/DaDe287/AutoVLESS/main/setup-firewall.sh)

x-ui restart

# --- ВЫТАСКИВАЕМ URL и пароль ---
PANEL_URL=$(echo "$INSTALL_OUTPUT" | grep -iE 'Access URL' | awk -F'URL: ' '{print $2}' | tr -d '[:space:]')
PASSWORD=$(echo "$INSTALL_OUTPUT" | grep -iE 'Password' | awk -F'Password: ' '{print $2}' | tr -d '[:space:]')
USERNAME=$(echo "$INSTALL_OUTPUT" | grep -iE 'Username' | awk -F'Username: ' '{print $2}' | tr -d '[:space:]')

# Подстраховка
[ -z "$PANEL_URL" ] && PANEL_URL="(не найден)"
[ -z "$PASSWORD" ] && PASSWORD="(не найден)"
[ -z "$USERNAME" ] && USERNAME="(не найден)"

# Обычно логин по умолчанию — admin

# Вывод в JSON формате
echo ""
echo "======================================="
echo "   Данные панели 3x-ui"
echo "======================================="
echo "{\"apiUrl\": \"${PANEL_URL}\", \"username\": \"${USERNAME}\", \"password\": \"${PASSWORD}\"}"
echo ""
