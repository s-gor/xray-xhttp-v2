#!/usr/bin/env bash

set -Eeuo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
    echo "Ошибка: запустите скрипт от root." >&2
    exit 1
fi

if [[ ! -r /etc/os-release ]]; then
    echo "Ошибка: не удалось определить операционную систему." >&2
    exit 1
fi

# shellcheck disable=SC1091
source /etc/os-release

case "${ID:-}" in
    ubuntu|debian)
        ;;
    *)
        echo "Ошибка: скрипт рассчитан на Ubuntu/Debian с systemd и apt." >&2
        exit 1
        ;;
esac

if ! command -v systemctl >/dev/null 2>&1; then
    echo "Ошибка: systemd не найден." >&2
    exit 1
fi

read -r -p "Введите свой домен без http:// и https://: " DOMAIN
DOMAIN="${DOMAIN,,}"
DOMAIN="${DOMAIN%.}"

if [[ ! "$DOMAIN" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$ ]]; then
    echo "Ошибка: некорректное имя домена: $DOMAIN" >&2
    exit 1
fi

LOG_FILE="/root/xray-xhttp-install.log"
VALUES_FILE="/root/xray-xhttp-values.env"
CLIENT_LINK_FILE="/root/xray-client-link.txt"

XRAY_CONFIG="/usr/local/etc/xray/config.json"
XRAY_INSTALLER_URL="https://github.com/XTLS/Xray-install/raw/main/install-release.sh"

NGINX_SITE="/etc/nginx/sites-available/xray-xhttp.conf"
NGINX_LINK="/etc/nginx/sites-enabled/xray-xhttp.conf"

CERT_DIR="/etc/ssl/xray"
WEB_ROOT="/var/www/html"
ACME_HOME="/root/.acme.sh"

XHTTP_LOCAL_PORT="8443"

TEMP_FILES=()

cleanup() {
    local file

    for file in "${TEMP_FILES[@]:-}"; do
        rm -f -- "$file"
    done
}

trap cleanup EXIT

: > "$LOG_FILE"
chmod 600 "$LOG_FILE"

exec > >(tee -a "$LOG_FILE") 2>&1

trap 'echo; echo "Ошибка на строке $LINENO. Установка остановлена. Журнал: $LOG_FILE" >&2' ERR

step() {
    printf '\n============================================================\n%s\n============================================================\n' "$1"
}

step "0. Проверка чистого сервера"

for existing_path in \
    "$VALUES_FILE" \
    "$CLIENT_LINK_FILE" \
    "$NGINX_SITE" \
    "$NGINX_LINK" \
    "$XRAY_CONFIG" \
    "/usr/local/bin/xray" \
    "$ACME_HOME"; do
    if [[ -e "$existing_path" || -L "$existing_path" ]]; then
        echo "Ошибка: найден существующий объект: $existing_path" >&2
        echo "Установщик предназначен для чистого сервера и не будет перезаписывать действующую установку." >&2
        exit 1
    fi
done

if [[ -d /etc/nginx/sites-enabled ]]; then
    mapfile -t EXISTING_NGINX_SITES < <(
        find /etc/nginx/sites-enabled -mindepth 1 -maxdepth 1 \
            ! -name default -printf '%f\n' 2>/dev/null || true
    )

    if [[ "${#EXISTING_NGINX_SITES[@]}" -gt 0 ]]; then
        echo "Ошибка: в Nginx уже включены другие сайты:" >&2
        printf '  %s\n' "${EXISTING_NGINX_SITES[@]}" >&2
        echo "Скрипт не будет изменять сервер с действующими сайтами." >&2
        exit 1
    fi
fi

step "1. Обновление системы и установка пакетов"

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get upgrade -y
apt-get install -y \
    curl \
    wget \
    unzip \
    tar \
    nginx \
    dnsutils \
    ca-certificates \
    openssl \
    cron

step "2. Запуск Nginx и cron"

systemctl enable --now nginx
systemctl enable --now cron

systemctl is-active --quiet nginx
systemctl is-active --quiet cron

step "3. Сохранение домена"

printf 'DOMAIN="%s"\n' "$DOMAIN" > "$VALUES_FILE"
chmod 600 "$VALUES_FILE"

step "4. Проверка DNS и доступности HTTP"

SERVER_IPV4="$(curl -4fsS --max-time 20 https://ifconfig.me)"
mapfile -t DOMAIN_IPV4_LIST < <(
    dig +short A "$DOMAIN" |
        grep -E '^[0-9]+(\.[0-9]+){3}$' || true
)

echo "IPv4 сервера: $SERVER_IPV4"

if [[ "${#DOMAIN_IPV4_LIST[@]}" -gt 0 ]]; then
    echo "A-записи домена: ${DOMAIN_IPV4_LIST[*]}"

    DNS_MATCH="no"

    for ip in "${DOMAIN_IPV4_LIST[@]}"; do
        if [[ "$ip" == "$SERVER_IPV4" ]]; then
            DNS_MATCH="yes"
            break
        fi
    done

    if [[ "$DNS_MATCH" != "yes" ]]; then
        echo "Предупреждение: A-запись домена не совпадает с IPv4 сервера."
        echo "Это допустимо, если домен проксируется через Cloudflare или другой CDN."
    fi
else
    echo "Ошибка: для $DOMAIN не найдена A-запись." >&2
    exit 1
fi

mkdir -p "$WEB_ROOT"

VERIFY_TOKEN="$(openssl rand -hex 16)"
VERIFY_FILE="$WEB_ROOT/.xray-xhttp-check-$VERIFY_TOKEN"
VERIFY_URL="http://$DOMAIN/.xray-xhttp-check-$VERIFY_TOKEN"

printf '%s\n' "$VERIFY_TOKEN" > "$VERIFY_FILE"
chmod 644 "$VERIFY_FILE"

HTTP_RESULT="$(curl -4fsSL --max-time 30 "$VERIFY_URL")"
rm -f -- "$VERIFY_FILE"

if [[ "$HTTP_RESULT" != "$VERIFY_TOKEN" ]]; then
    echo "Ошибка: домен доступен, но запрос не пришёл на этот сервер." >&2
    echo "Проверьте DNS, порт 80, Security Group и сетевой firewall." >&2
    exit 1
fi

echo "HTTP-проверка пройдена."

step "5. Создание веб-страницы"

cat > "$WEB_ROOT/index.html" <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$DOMAIN</title>
  <style>
    body {
      font-family: Arial, sans-serif;
      margin: 40px;
      line-height: 1.6;
    }

    main {
      max-width: 720px;
    }

    code {
      background: #f4f4f4;
      padding: 2px 6px;
      border-radius: 4px;
    }
  </style>
</head>
<body>
  <main>
    <h1>$DOMAIN</h1>
    <p>This site is online.</p>
    <p>Status: <code>ok</code></p>
  </main>
</body>
</html>
EOF

chmod 644 "$WEB_ROOT/index.html"

PAGE_CHECK="$(curl -4fsSL --max-time 30 "http://$DOMAIN")"

if [[ "$PAGE_CHECK" != *"<h1>$DOMAIN</h1>"* ]]; then
    echo "Ошибка: созданная веб-страница не открывается через домен." >&2
    exit 1
fi

step "6. Установка acme.sh и выпуск сертификата"

ACME_INSTALLER="$(mktemp)"
TEMP_FILES+=("$ACME_INSTALLER")

curl -fsSL --retry 3 \
    https://get.acme.sh \
    -o "$ACME_INSTALLER"

sh "$ACME_INSTALLER"

"$ACME_HOME/acme.sh" --set-default-ca --server letsencrypt

"$ACME_HOME/acme.sh" \
    --issue \
    -d "$DOMAIN" \
    --webroot "$WEB_ROOT"

mkdir -p "$CERT_DIR"

install -m 600 /dev/null "$CERT_DIR/private.key"
install -m 644 /dev/null "$CERT_DIR/fullchain.cer"

"$ACME_HOME/acme.sh" \
    --install-cert \
    -d "$DOMAIN" \
    --key-file "$CERT_DIR/private.key" \
    --fullchain-file "$CERT_DIR/fullchain.cer" \
    --reloadcmd "/usr/bin/systemctl reload nginx"

test -s "$CERT_DIR/private.key"
test -s "$CERT_DIR/fullchain.cer"
crontab -l | grep -q '/\.acme\.sh/acme\.sh'

step "7. Установка Xray"

XRAY_INSTALLER="$(mktemp)"
TEMP_FILES+=("$XRAY_INSTALLER")

curl -fsSL --retry 3 \
    "$XRAY_INSTALLER_URL" \
    -o "$XRAY_INSTALLER"

chmod 700 "$XRAY_INSTALLER"
bash "$XRAY_INSTALLER"

xray version

step "8. Создание рабочих значений Xray"

XHTTP_PATH="/$(openssl rand -hex 8)"
USER_UUID="$(xray uuid)"

printf 'DOMAIN="%s"\nXHTTP_LOCAL_PORT="%s"\nXHTTP_PATH="%s"\nUSER_UUID="%s"\n' \
    "$DOMAIN" \
    "$XHTTP_LOCAL_PORT" \
    "$XHTTP_PATH" \
    "$USER_UUID" > "$VALUES_FILE"

chmod 600 "$VALUES_FILE"

step "9. Создание конфигурации Xray"

mkdir -p "$(dirname "$XRAY_CONFIG")"

cat > "$XRAY_CONFIG" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "vless-xhttp-in",
      "listen": "127.0.0.1",
      "port": $XHTTP_LOCAL_PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$USER_UUID",
            "email": "user@$DOMAIN"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "xhttpSettings": {
          "path": "$XHTTP_PATH"
        }
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {}
    },
    {
      "tag": "blocked",
      "protocol": "blackhole",
      "settings": {}
    }
  ]
}
EOF

chown root:root "$XRAY_CONFIG"
chmod 644 "$XRAY_CONFIG"

xray run -test -config "$XRAY_CONFIG"

systemctl enable xray
systemctl restart xray
systemctl is-active --quiet xray

step "10. Создание конфигурации Nginx"

cat > "$NGINX_SITE" <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    root $WEB_ROOT;
    index index.html;

    location /.well-known/acme-challenge/ {
        root $WEB_ROOT;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate     $CERT_DIR/fullchain.cer;
    ssl_certificate_key $CERT_DIR/private.key;

    root $WEB_ROOT;
    index index.html;

    location ~ ^$XHTTP_PATH(/|\$) {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:$XHTTP_LOCAL_PORT;

        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_buffering off;
        proxy_request_buffering off;
    }

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

chmod 644 "$NGINX_SITE"

rm -f /etc/nginx/sites-enabled/default
ln -sfn "$NGINX_SITE" "$NGINX_LINK"

nginx -t
systemctl reload nginx
systemctl is-active --quiet nginx

step "11. Создание клиентской ссылки"

ENCODED_PATH="${XHTTP_PATH//\//%2F}"

CLIENT_LINK="vless://${USER_UUID}@${DOMAIN}:443?encryption=none&security=tls&sni=${DOMAIN}&host=${DOMAIN}&type=xhttp&path=${ENCODED_PATH}#${DOMAIN}-xhttp"

printf '%s\n' "$CLIENT_LINK" > "$CLIENT_LINK_FILE"
chmod 600 "$CLIENT_LINK_FILE"

step "12. Финальная проверка"

nginx -t
xray run -test -config "$XRAY_CONFIG"

systemctl is-active --quiet nginx
systemctl is-active --quiet cron
systemctl is-active --quiet xray

ss -ltnp | grep -Fq "127.0.0.1:$XHTTP_LOCAL_PORT"
ss -ltnp | grep -Eq '(^|[[:space:]])[^[:space:]]*:443[[:space:]]'

curl -4fsSI --max-time 30 "https://$DOMAIN" > /dev/null

echo |
    openssl s_client \
        -connect "$DOMAIN:443" \
        -servername "$DOMAIN" \
        -verify_return_error 2>&1 |
    grep -q 'Verify return code: 0 (ok)'

crontab -l | grep -q '/\.acme\.sh/acme\.sh'

grep -Fq "\"path\": \"$XHTTP_PATH\"" "$XRAY_CONFIG"
nginx -T 2>/dev/null | grep -Fq "location ~ ^$XHTTP_PATH(/|$)"
grep -Fq "path=$ENCODED_PATH" "$CLIENT_LINK_FILE"

printf '\nУстановка завершена успешно.\n\n'
printf 'Домен: %s\n' "$DOMAIN"
printf 'Xray: 127.0.0.1:%s\n' "$XHTTP_LOCAL_PORT"
printf 'XHTTP path: %s\n' "$XHTTP_PATH"
printf 'Рабочие значения: %s\n' "$VALUES_FILE"
printf 'Клиентская ссылка: %s\n' "$CLIENT_LINK_FILE"
printf 'Журнал установки: %s\n\n' "$LOG_FILE"

printf '%s\n\n' "$CLIENT_LINK"

printf 'ВАЖНО: если в клиенте уже есть профиль для этого домена,\n'
printf 'удалите старый профиль и импортируйте именно новую ссылку.\n'
