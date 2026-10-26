clear

sudo apt-get update && sudo apt-get upgrade -y

cat > /etc/sysctl.d/99-vpn-tune.conf << 'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 8192
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
EOF
sysctl --system

sudo apt-get install -y ufw

ufw --force reset
ufw default deny incoming
ufw default allow outgoing
for p in 22 80 443 8443 5506; do ufw allow $p/tcp; done
ufw --force enable

# IPTABLES 
## Block Torrents trafic
echo "Y" | sudo apt install iptables
iptables -A FORWARD -p tcp --dport 6881:6999 -j DROP
iptables -A FORWARD -p udp --dport 6881:6999 -j DROP

# Trafic-Guard
## Block Any scanners to the server
curl -fsSL https://raw.githubusercontent.com/DaDe287/Traffic-Guard/refs/heads/main/install.sh | sudo bash

#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

die() { echo "Ошибка: $*" >&2; }

[[ $EUID -eq 0 ]] || die "Запустите через sudo bash."
[[ -d /run/systemd/system ]] || die "Нужен systemd."
command -v apt-get >/dev/null || die "Нужен Debian/Ubuntu."
[[ ! -e /etc/x-ui/x-ui.db && ! -e /usr/local/x-ui ]] ||
    die "3x-ui уже установлена. Скрипт предназначен для чистой установки."

CDN_DOMAIN=""
read -r -p "Введите cdn-домен: " CDN_DOMAIN </dev/tty ||
    die "Не удалось прочитать ввод из терминала."

[[ -n "$CDN_DOMAIN" ]] || die "cdn-Домен не может быть пустым."

DOMAIN=""
read -r -p "Введите домен панели: " DOMAIN </dev/tty ||
    die "Не удалось прочитать ввод из терминала."

[[ -n "$DOMAIN" ]] || die "Домен не может быть пустым."

[[ ${#DOMAIN} -le 253 && "$DOMAIN" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$ ]] ||
    die "Введите домен без https://, порта и пути."

# Логи — stderr, итоговый JSON — stdout.
exec 3>&1
exec 1>&2

export DEBIAN_FRONTEND=noninteractive
echo "[1/4] Домен принят: $DOMAIN" >&2

echo "[2/4] Обновление списка пакетов..." >&2
apt-get update

echo "[3/4] Установка зависимостей..." >&2
apt-get install -y \
    curl ca-certificates dnsutils openssl jq iproute2 cron

echo "[4/4] Определение IP и проверка DNS..." >&2
SERVER_IP=$(
    curl -4fsS --connect-timeout 10 --max-time 20 https://api4.ipify.org
) || die "Не удалось определить публичный IPv4."

[[ "$SERVER_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] ||
    die "Некорректный IPv4."

# Проверяем A через два публичных DNS-сервера.
for resolver in 1.1.1.1 8.8.8.8; do
    answer=$(dig @"$resolver" +time=5 +tries=1 +short A "$DOMAIN") ||
        die "DNS-сервер $resolver недоступен."

    addresses=$(
        awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/' <<< "$answer" |
            sort -u
    )

    [[ "$addresses" == "$SERVER_IP" ]] ||
        die "A через $resolver: [$addresses]; IP сервера: $SERVER_IP."

    answer=$(dig @"$resolver" +time=5 +tries=1 +short AAAA "$DOMAIN") ||
        die "Не удалось проверить AAAA."

    [[ "$answer" != *:* ]] ||
        die "Этот скрипт рассчитан на IPv4: обнаружена AAAA-запись."
done

for port in 80 5506; do
    [[ -z "$(ss -H -ltn "sport = :$port")" ]] ||
        die "TCP-порт $port занят."
done

echo "DNS проверен: $DOMAIN → $SERVER_IP"

USERNAME="${DOMAIN%%.*}.admin"

# Случайный секретный путь: 32 символа.
WEB_BASE_PATH="$(openssl rand -hex 8)"

# 19 случайных букв, обязательно оба регистра.
while :; do
    PASSWORD=$(openssl rand -base64 48 | tr -dc 'A-Za-z' | cut -c1-19)
    [[ ${#PASSWORD} -eq 19 &&
       "$PASSWORD" == *[a-z]* &&
       "$PASSWORD" == *[A-Z]* ]] && break
done

# Добавляем случайный спецсимвол.
symbols='!@#%+=_-'
random_byte=$(openssl rand -hex 1)
index=$((16#$random_byte % 8))
PASSWORD+="${symbols:index:1}"

installer=$(mktemp)
trap 'rm -f "$installer"' EXIT

curl -fsSL --retry 3 \
    https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh \
    -o "$installer"

# Проверка наличия параметров автоматического режима.
for variable in \
    XUI_NONINTERACTIVE XUI_DB_TYPE XUI_PANEL_PORT XUI_SSL_MODE XUI_DOMAIN
do
    grep -q "$variable" "$installer" ||
        die "Интерфейс установщика изменился: отсутствует $variable."
done

# SQLite, порт, учетные данные и SSL — без ручных ответов.
# Установщик выпускает сертификат, подключает его и настраивает продление.
XUI_NONINTERACTIVE=1 \
XUI_DB_TYPE=sqlite \
XUI_USERNAME="$USERNAME" \
XUI_PASSWORD="$PASSWORD" \
XUI_PANEL_PORT=5506 \
XUI_WEB_BASE_PATH="/$WEB_BASE_PATH/" \
XUI_SSL_MODE=domain \
XUI_DOMAIN="$DOMAIN" \
XUI_ACME_HTTP_PORT=80 \
    bash "$installer" v2.9.4 </dev/null

cert_dir="/root/cert/$DOMAIN"

[[ -s "$cert_dir/fullchain.pem" && -s "$cert_dir/privkey.pem" ]] ||
    die "SSL не выпущен. Проверьте журнал выше и доступность TCP/80."

# Применяем окончательные настройки через CLI панели.
/usr/local/x-ui/x-ui setting \
    -username "$USERNAME" \
    -password "$PASSWORD" \
    -port 5506 \
    -webBasePath "/$WEB_BASE_PATH/"

/usr/local/x-ui/x-ui cert \
    -webCert "$cert_dir/fullchain.pem" \
    -webCertKey "$cert_dir/privkey.pem"

systemctl enable --now cron
systemctl restart x-ui

API_URL="https://$DOMAIN:5506/$WEB_BASE_PATH"

# Ждем запуска, проверяя TLS без отключения проверки сертификата.
ready=0
for attempt in {1..20}; do
    if curl --noproxy '*' -fsS --connect-timeout 2 --max-time 5 \
        --resolve "$DOMAIN:5506:127.0.0.1" \
        "$API_URL/" >/dev/null 2>&1
    then
        ready=1
        break
    fi
    sleep 1
done

[[ "$ready" == 1 ]] ||
    die "Панель не отвечает по HTTPS. Проверьте journalctl -u x-ui."

# Проверяем вход с созданными логином и паролем.
reply=$(curl --noproxy '*' -fsS --max-time 15 \
    --resolve "$DOMAIN:5506:127.0.0.1" \
    --data-urlencode "username=$USERNAME" \
    --data-urlencode "password=$PASSWORD" \
    "$API_URL/login")

jq -e '.success == true' <<< "$reply" >/dev/null ||
    die "Проверка входа не прошла."

echo "Установка завершена. Панель доступна по адресу: $API_URL"

printf '\n' >&3

jq -cn \
    --arg apiUrl "$API_URL" \
    --arg username "$USERNAME" \
    --arg password "$PASSWORD" \
    '{apiUrl:$apiUrl, username:$username, password:$password}' >&3

printf '\n' >&3

sudo apt-get install -y certbot nginx

systemctl stop nginx

certbot certonly --standalone -d "${DOMAIN}" \
    --non-interactive --agree-tos -m "webmaster@${DOMAIN}" --no-eff-email



sudo tee /etc/nginx/sites-available/xhttp-serv.conf > /dev/null <<EOF
server {
    listen 443 ssl http2 default_server;
    server_name ${DOMAIN} ${CDN_DOMAIN} _;

    ssl_certificate     /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    root /var/www/html;
    index index.html;

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;

    # ========================================
    # xHTTP-тоннель замаскирован под API сайта
    # ========================================
    location /v2/api/users {
        client_max_body_size 0;
        proxy_pass http://127.0.0.1:10085;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_cache off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        send_timeout 3600s;
    }

    location / {
        expires 1h;
        add_header Cache-Control "public" always;
        try_files $uri $uri/ /index.html;
    }

    # Закрываем стандартные дыры
    location ~ /\.(env|git|svn|htaccess|aws) { return 444; }
    location ~ /wp-(login|admin|content) { return 444; }
    location ~ /phpmyadmin { return 444; }
}
EOF

sudo unlink /etc/nginx/sites-enabled/default

sudo ln -s /etc/nginx/sites-available/xhttp-serv.conf /etc/nginx/sites-enabled

nginx -t

sudo apt-get install -y git

REPOS=(
    startbootstrap-agency
    startbootstrap-creative
    startbootstrap-freelancer
    startbootstrap-modern-business
    startbootstrap-business-casual
    startbootstrap-personal
)

TEMPLATE=$(printf '%s\n' "${REPOS[@]}" | shuf -n 1)
echo "Выбран шаблон: ${TEMPLATE}"

cd /tmp || exit 1
WORK_DIR=$(mktemp -d /tmp/bootstrap.XXXXXXXX) || exit 1

if ! git clone --depth 1 \
    "https://github.com/StartBootstrap/${TEMPLATE}.git" \
    "${WORK_DIR}/repo"; then
    rm -rf -- "$WORK_DIR"
    exit 1
fi

if [[ ! -f "${WORK_DIR}/repo/dist/index.html" ]]; then
    echo "В шаблоне отсутствует dist/index.html." >&2
    rm -rf -- "$WORK_DIR"
    exit 1
fi

rm -rf /var/www/html
mkdir -p /var/www/html || exit 1
cp -a "${WORK_DIR}/repo/dist/." /var/www/html/ || exit 1

rm -rf -- "$WORK_DIR"

systemctl restart nginx
x-ui restart

mkdir -p /root/scripts/

sudo tee /root/scripts/renew-xhttp-serv.sh > /dev/null <<EOF
systemctl stop nginx
cd /opt/remnanode && docker compose stop

certbot certonly --standalone -d "${DOMAIN}" \
    --non-interactive --agree-tos -m "webmaster@${DOMAIN}" --no-eff-email --force-renewal

cd /opt/remnanode && docker compose start
systemctl start nginx
EOF

echo "Y" | sudo apt install cron

echo "0 3 1 2,4,6,8,10,12 * bash /root/scripts/renew-self-xhttp-serv.sh" > /var/spool/cron/crontabs/root
