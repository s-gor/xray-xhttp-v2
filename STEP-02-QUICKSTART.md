## Быстрая установка: только команды

### 1. Установить пакеты

```bash
apt update && apt upgrade -y
apt install -y curl wget unzip tar nginx dnsutils ca-certificates openssl cron
systemctl enable --now nginx
systemctl enable --now cron
```

### 2. Сохранить домен

```bash
bash -c 'read -rp "Enter your domain: " DOMAIN; printf "DOMAIN=\"%s\"\n" "$DOMAIN" > /root/xray-xhttp-values.env; chmod 600 /root/xray-xhttp-values.env; cat /root/xray-xhttp-values.env'
```

### 3. Проверить IP, DNS и HTTP

```bash
curl -4 ifconfig.me

bash -c 'source /root/xray-xhttp-values.env; dig +short "$DOMAIN"'

bash -c 'source /root/xray-xhttp-values.env; curl -I "http://$DOMAIN"'
```

### 4. Создать веб-страницу

```bash
source /root/xray-xhttp-values.env

cat > /var/www/html/index.html <<EOF
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
```

### 5. Выпустить сертификат

```bash
curl https://get.acme.sh | sh

/root/.acme.sh/acme.sh --set-default-ca --server letsencrypt

bash -c 'source /root/xray-xhttp-values.env; /root/.acme.sh/acme.sh --issue -d "$DOMAIN" --webroot /var/www/html'

mkdir -p /etc/ssl/xray

bash -c 'source /root/xray-xhttp-values.env; /root/.acme.sh/acme.sh --install-cert -d "$DOMAIN" --key-file /etc/ssl/xray/private.key --fullchain-file /etc/ssl/xray/fullchain.cer --reloadcmd "/usr/bin/systemctl reload nginx"'
```

### 6. Настроить HTTPS в Nginx

```bash
source /root/xray-xhttp-values.env

cat > /etc/nginx/sites-available/xray-xhttp.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    root /var/www/html;
    index index.html;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate     /etc/ssl/xray/fullchain.cer;
    ssl_certificate_key /etc/ssl/xray/private.key;

    root /var/www/html;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

rm -f /etc/nginx/sites-enabled/default

ln -sf /etc/nginx/sites-available/xray-xhttp.conf /etc/nginx/sites-enabled/xray-xhttp.conf

nginx -t

systemctl reload nginx
```

### 7. Установить Xray

```bash
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)"

xray version
```

### 8. Создать рабочие значения

```bash
bash -c 'source /root/xray-xhttp-values.env; XHTTP_LOCAL_PORT="8443"; XHTTP_PATH="/$(openssl rand -hex 8)"; USER_UUID="$(xray uuid)"; printf "DOMAIN=\"%s\"\nXHTTP_LOCAL_PORT=\"%s\"\nXHTTP_PATH=\"%s\"\nUSER_UUID=\"%s\"\n" "$DOMAIN" "$XHTTP_LOCAL_PORT" "$XHTTP_PATH" "$USER_UUID" > /root/xray-xhttp-values.env; chmod 600 /root/xray-xhttp-values.env; cat /root/xray-xhttp-values.env'
```

### 9. Создать конфигурацию Xray

```bash
source /root/xray-xhttp-values.env

cat > /usr/local/etc/xray/config.json <<EOF
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

chown root:root /usr/local/etc/xray/config.json
chmod 644 /usr/local/etc/xray/config.json

xray run -test -config /usr/local/etc/xray/config.json

systemctl restart xray
```

### 10. Добавить XHTTP в Nginx

```bash
source /root/xray-xhttp-values.env

cp /etc/nginx/sites-available/xray-xhttp.conf /etc/nginx/sites-available/xray-xhttp.conf.bak

cat > /etc/nginx/sites-available/xray-xhttp.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    root /var/www/html;
    index index.html;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate     /etc/ssl/xray/fullchain.cer;
    ssl_certificate_key /etc/ssl/xray/private.key;

    root /var/www/html;
    index index.html;

    location ~ ^$XHTTP_PATH(/|$) {
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

nginx -t

systemctl reload nginx
```

### 11. Создать клиентскую ссылку

```bash
bash -c 'source /root/xray-xhttp-values.env; ENCODED_PATH="${XHTTP_PATH//\//%2F}"; CLIENT_LINK="vless://${USER_UUID}@${DOMAIN}:443?encryption=none&security=tls&sni=${DOMAIN}&host=${DOMAIN}&type=xhttp&path=${ENCODED_PATH}#${DOMAIN}-xhttp"; echo "$CLIENT_LINK" | tee /root/xray-client-link.txt'
```

### 12. Проверить

```bash
nginx -t

systemctl is-active nginx
systemctl is-active cron
systemctl is-active xray

ss -tulpn | grep :8443

crontab -l | grep acme.sh

journalctl -u xray -n 20 --no-pager

bash -c 'source /root/xray-xhttp-values.env; curl -I "https://$DOMAIN"'

cat /root/xray-client-link.txt
```

