#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

die() { echo "Ошибка: $*" >&2; }

[[ $EUID -eq 0 ]] || die "Запустите через sudo bash."
[[ -d /run/systemd/system ]] || die "Нужен systemd."
command -v apt-get >/dev/null || die "Нужен Debian/Ubuntu."
[[ ! -e /etc/x-ui/x-ui.db && ! -e /usr/local/x-ui ]] ||
    die "3x-ui уже установлена. Скрипт предназначен для чистой установки."

DOMAIN="${1:-}"
[[ -n "$DOMAIN" ]] || read -rp "Домен панели: " DOMAIN
DOMAIN="${DOMAIN,,}"
DOMAIN="${DOMAIN%.}"

[[ ${#DOMAIN} -le 253 && "$DOMAIN" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$ ]] ||
    die "Введите домен без https://, порта и пути."

# Логи — stderr, итоговый JSON — stdout.
exec 3>&1
exec 1>&2

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y \
    curl ca-certificates dnsutils openssl jq iproute2 cron

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
