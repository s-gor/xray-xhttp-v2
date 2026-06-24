# Xray + XHTTP + Nginx + Let's Encrypt

![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04%20%7C%2026.04-E95420?logo=ubuntu&logoColor=white)
![Nginx](https://img.shields.io/badge/Nginx-HTTPS-009639?logo=nginx&logoColor=white)
![Xray](https://img.shields.io/badge/Xray-XHTTP-2F80ED)
![Let's Encrypt](https://img.shields.io/badge/Let's%20Encrypt-TLS-003A70?logo=letsencrypt&logoColor=white)

Пошаговая настройка Xray XHTTP за Nginx с TLS-сертификатом Let's Encrypt.

Инструкция проверена на чистом сервере.

Итоговая схема:

```text
Клиент:443
Nginx:443
Xray:127.0.0.1:8443
```

Снаружи открыты только:

```text
80/tcp
443/tcp
```

Xray слушает только локальный адрес:

```text
127.0.0.1:8443
```

Порт `8443/tcp` наружу открывать не нужно.

---

## Варианты установки

### Быстрая ручная установка

[Открыть STEP-02-QUICKSTART.md](STEP-02-QUICKSTART.md)

### One-line Install

[Открыть STEP-03-ONE-LINE-INSTAL.md](STEP-03-ONE-LINE-INSTAL.md)

### One-line Uninstall

[Открыть STEP-04-UNINSTALL.md](STEP-04-UNINSTALL.md)

---

## Для кого эта инструкция

Инструкция рассчитана на тех, кто хочет не только выполнить команды, но и понимать последовательность настройки.

После каждого важного действия показано:

- что выполняется;
- какую команду запускать;
- какой результат считать правильным;
- где находятся созданные файлы.

Если вы только начали разбираться с Linux, Nginx, TLS-сертификатами или Xray, выполняйте шаги по порядку и не пропускайте проверки.

---

## Как выполнять команды

Все команды выполняются на сервере от `root`.

Короткие команды можно копировать и выполнять отдельно.

Большие блоки с `cat <<EOF` создают конфигурационные файлы.

Перед такими блоками используется инструкция:

> Скопируйте весь блок целиком и вставьте его в терминал одной командой.

Обязательно копируйте весь блок, включая последнюю строку `EOF`.

В инструкции не используется `nano`.

Домен, локальный порт, XHTTP path и UUID сохраняются в файле:

```text
/root/xray-xhttp-values.env
```

Затем эти значения автоматически подставляются в конфигурацию Xray, конфигурацию Nginx и клиентскую ссылку.

---

## Содержание

1. Требования
2. Обновить сервер и установить пакеты
3. Запустить Nginx и cron
4. Указать домен
5. Проверить IPv4, DNS и HTTP
6. Создать веб-страницу
7. Выпустить TLS-сертификат
8. Настроить HTTPS в Nginx
9. Установить Xray
10. Создать рабочие значения Xray
11. Создать конфигурацию Xray
12. Добавить XHTTP в Nginx
13. Создать клиентскую ссылку
14. Финальная проверка
15. Возможные ошибки
16. Важные файлы

---

## 1. Требования

Нужен сервер с Ubuntu Server 24.04 LTS, Ubuntu Server 26.04 LTS или совместимой Ubuntu/Debian-системой.

Также нужен домен или DDNS-адрес с A-записью, указывающей на внешний IPv4 сервера.

На сервере, маршрутизаторе или в Security Group должны быть открыты входящие порты:

| Порт | Назначение |
|---|---|
| `80/tcp` | HTTP и проверка домена Let's Encrypt |
| `443/tcp` | HTTPS и клиентское подключение |

Порт `8443/tcp` наружу открывать не нужно.

Он используется только внутри сервера:

```text
Nginx
127.0.0.1:8443
Xray
```

---

## 2. Обновить сервер и установить пакеты

Обновить систему:

```bash
apt update && apt upgrade -y
```

Установить необходимые пакеты:

```bash
apt install -y curl wget unzip tar nginx dnsutils ca-certificates openssl cron
```

Назначение пакетов:

| Пакет | Назначение |
|---|---|
| `curl`, `wget` | загрузка файлов и проверка HTTP/HTTPS |
| `unzip`, `tar` | работа с архивами |
| `nginx` | приём HTTP/HTTPS-подключений |
| `dnsutils` | команда `dig` для проверки DNS |
| `ca-certificates` | доверенные корневые сертификаты |
| `openssl` | генерация случайного XHTTP path |
| `cron` | автоматическое продление TLS-сертификата |

Если часть пакетов уже установлена, `apt` оставит их без изменений или обновит до актуальной версии.

---

## 3. Запустить Nginx и cron

Запустить службы и добавить их в автозагрузку:

```bash
systemctl enable --now nginx
systemctl enable --now cron
```

Проверить состояние:

```bash
printf 'Nginx: '
systemctl is-active nginx

printf 'Cron:  '
systemctl is-active cron
```

Ожидаемый результат:

```text
Nginx: active
Cron:  active
```

Проверить, что Nginx слушает порт `80`:

```bash
ss -ltnp | grep ':80'
```

Правильно, если видна строка с адресом `:80`.

---

## 4. Указать домен

Введите домен без `http://`, `https://` и завершающего `/`.

```bash
read -rp "Введите домен: " DOMAIN && DOMAIN="${DOMAIN,,}" && DOMAIN="${DOMAIN%.}" && printf 'DOMAIN="%s"\n' "$DOMAIN" > /root/xray-xhttp-values.env && chmod 600 /root/xray-xhttp-values.env
```

Проверить сохранённое значение:

```bash
cat /root/xray-xhttp-values.env
```

Ожидаемый результат:

```text
DOMAIN="ваш-домен"
```

Файл создаётся с правами `600`, потому что позднее в нём будут храниться UUID и другие рабочие значения.

---

## 5. Проверить IPv4, DNS и HTTP

```bash
source /root/xray-xhttp-values.env && printf '\nIPv4 сервера: ' && curl -4fsS ifconfig.me && echo && printf '\nA-запись домена:\n' && dig +short A "$DOMAIN" && printf '\nHTTP:\n' && curl -sS -o /dev/null -w 'HTTP %{http_code}\n' "http://$DOMAIN"
```

Проверьте:

- внешний IPv4 сервера совпадает с A-записью домена;
- HTTP возвращает код `200`.

Пример:

```text
IPv4 сервера: 203.0.113.10

A-запись домена:
203.0.113.10

HTTP:
HTTP 200
```

Если ответа нет, проверьте:

- A-запись домена;
- входящий порт `80/tcp`;
- Security Group или сетевой firewall;
- состояние Nginx.

---

## 6. Создать веб-страницу

Обычные запросы к домену должны открывать обычную веб-страницу.

Xray будет доступен только по отдельному случайному XHTTP path.

Скопируйте весь блок целиком и вставьте его в терминал одной командой.

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

Проверить страницу:

```bash
source /root/xray-xhttp-values.env
curl -sS -o /dev/null -w 'HTTP %{http_code}\n' "http://$DOMAIN"
```

Ожидаемый результат:

```text
HTTP 200
```

---

## 7. Выпустить TLS-сертификат

TLS-сертификат нужен для HTTPS-подключения на порту `443`.

Скопируйте весь блок целиком и вставьте его в терминал одной командой.

```bash
curl -fsSL https://get.acme.sh | sh

/root/.acme.sh/acme.sh --set-default-ca --server letsencrypt

source /root/xray-xhttp-values.env

/root/.acme.sh/acme.sh \
  --issue \
  -d "$DOMAIN" \
  --webroot /var/www/html

mkdir -p /etc/ssl/xray

/root/.acme.sh/acme.sh \
  --install-cert \
  -d "$DOMAIN" \
  --key-file /etc/ssl/xray/private.key \
  --fullchain-file /etc/ssl/xray/fullchain.cer \
  --reloadcmd "/usr/bin/systemctl reload nginx"

if ! crontab -l 2>/dev/null | grep -E 'acme\.sh.*--cron' >/dev/null; then
  /root/.acme.sh/acme.sh --install-cronjob
fi
```

Проверить сертификат и автоматическое продление:

```bash
printf 'Private key: '
if test -s /etc/ssl/xray/private.key; then echo OK; else echo FAIL; fi

printf 'Certificate: '
if test -s /etc/ssl/xray/fullchain.cer; then echo OK; else echo FAIL; fi

printf 'Renewal cron: '
if crontab -l 2>/dev/null | grep -E 'acme\.sh.*--cron' >/dev/null; then echo OK; else echo FAIL; fi
```

Ожидаемый результат:

```text
Private key: OK
Certificate: OK
Renewal cron: OK
```

> [!IMPORTANT]
> Если Let's Encrypt сообщает `rateLimited` или `too many certificates`, повторные запуски не помогут.
>
> Используйте другой домен или дождитесь времени `retry after`, указанного в сообщении.

---

## 8. Настроить HTTPS в Nginx

На этом этапе Nginx начинает обслуживать обычную страницу по HTTPS.

Xray пока не участвует.

Скопируйте весь блок целиком и вставьте его в терминал одной командой.

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
    listen 443 ssl;
    http2 on;

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
ln -sfn /etc/nginx/sites-available/xray-xhttp.conf /etc/nginx/sites-enabled/xray-xhttp.conf

nginx -t && systemctl reload nginx
```

Ожидаемый результат:

```text
syntax is ok
test is successful
```

Проверить HTTPS:

```bash
source /root/xray-xhttp-values.env
curl -sS -o /dev/null -w 'HTTPS %{http_code}\n' "https://$DOMAIN"
```

Ожидаемый результат:

```text
HTTPS 200
```

---

## 9. Установить Xray

Установить Xray официальным установочным скриптом:

```bash
bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)"
```

Проверить установку:

```bash
xray version
systemctl status xray --no-pager -l
```

Правильно, если:

- выводится версия Xray;
- существует служба `xray.service`.

Сообщение установщика о возможном удалении `curl` и `unzip` выполнять не нужно.

---

## 10. Создать рабочие значения Xray

На этом этапе создаются:

- локальный порт Xray `8443`;
- случайный XHTTP path;
- UUID первого пользователя.

Параметр `mode` в базовой конфигурации не задаётся.

Скопируйте весь блок целиком и вставьте его в терминал одной командой.

```bash
source /root/xray-xhttp-values.env

XHTTP_LOCAL_PORT="8443"
XHTTP_PATH="/$(openssl rand -hex 8)"
USER_UUID="$(xray uuid)"

printf 'DOMAIN="%s"\nXHTTP_LOCAL_PORT="%s"\nXHTTP_PATH="%s"\nUSER_UUID="%s"\n' \
  "$DOMAIN" \
  "$XHTTP_LOCAL_PORT" \
  "$XHTTP_PATH" \
  "$USER_UUID" \
  > /root/xray-xhttp-values.env

chmod 600 /root/xray-xhttp-values.env
```

Проверить файл:

```bash
cat /root/xray-xhttp-values.env
```

Должны быть четыре заполненные строки:

```text
DOMAIN="ваш-домен"
XHTTP_LOCAL_PORT="8443"
XHTTP_PATH="/случайный-путь"
USER_UUID="uuid-пользователя"
```

> [!IMPORTANT]
> Не переходите к следующему шагу, если `XHTTP_LOCAL_PORT`, `XHTTP_PATH` или `USER_UUID` пустые.
>
> Иначе в конфигурации Nginx может появиться неправильный адрес:
>
> ```text
> proxy_pass http://127.0.0.1:;
> ```

> [!WARNING]
> Выполняйте этот блок один раз.
>
> Повторный запуск создаст новый XHTTP path и новый UUID. После этого потребуется заново создать конфигурацию Xray, конфигурацию Nginx и клиентскую ссылку.

---

## 11. Создать конфигурацию Xray

Xray будет слушать только:

```text
127.0.0.1:8443
```

UUID, порт и XHTTP path берутся из рабочего файла.

Скопируйте весь блок целиком и вставьте его в терминал одной командой.

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

xray run -test -config /usr/local/etc/xray/config.json &&
systemctl enable xray &&
systemctl restart xray
```

Проверить службу и локальный порт:

```bash
source /root/xray-xhttp-values.env

printf 'Xray service: '
systemctl is-active xray

printf 'Xray local port: '
if ss -ltnp | grep -F "127.0.0.1:$XHTTP_LOCAL_PORT" >/dev/null; then echo OK; else echo FAIL; fi
```

Ожидаемый результат:

```text
Xray service: active
Xray local port: OK
```

Если Xray не запустился:

```bash
systemctl status xray --no-pager -l
journalctl -u xray -n 50 --no-pager
```

---

## 12. Добавить XHTTP в Nginx

Nginx должен передавать запросы с сохранённым XHTTP path на Xray.

Скопируйте весь блок целиком и вставьте его в терминал одной командой.

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
    listen 443 ssl;
    http2 on;

    server_name $DOMAIN;

    ssl_certificate     /etc/ssl/xray/fullchain.cer;
    ssl_certificate_key /etc/ssl/xray/private.key;

    root /var/www/html;
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

nginx -t && systemctl reload nginx
```

Ожидаемый результат:

```text
syntax is ok
test is successful
```

Проверить активную конфигурацию:

```bash
source /root/xray-xhttp-values.env
nginx -T 2>/dev/null | grep -E "listen 443|http2 on|location ~|proxy_pass"
```

В выводе должны быть:

```text
listen 443 ssl;
http2 on;
ваш XHTTP path
proxy_pass http://127.0.0.1:8443;
```

---

## 13. Создать клиентскую ссылку

Параметр `mode` в ссылку не добавляется.

Скопируйте весь блок целиком и вставьте его в терминал одной командой.

```bash
source /root/xray-xhttp-values.env

ENCODED_PATH="${XHTTP_PATH//\//%2F}"

CLIENT_LINK="vless://${USER_UUID}@${DOMAIN}:443?encryption=none&security=tls&sni=${DOMAIN}&host=${DOMAIN}&type=xhttp&path=${ENCODED_PATH}#${DOMAIN}-xhttp"

printf '%s\n' "$CLIENT_LINK" | tee /root/xray-client-link.txt
chmod 600 /root/xray-client-link.txt
```

Импортируйте полученную ссылку в клиент.

Если в клиенте уже есть старый профиль для этого домена, удалите его и импортируйте новую ссылку.

---

## 14. Финальная проверка

Скопируйте весь блок целиком и вставьте его в терминал одной командой.

```bash
source /root/xray-xhttp-values.env

printf 'Nginx config:  '
if nginx -t >/dev/null 2>&1; then echo OK; else echo FAIL; fi

printf 'Nginx service: '
if systemctl is-active --quiet nginx; then echo OK; else echo FAIL; fi

printf 'Cron service:  '
if systemctl is-active --quiet cron; then echo OK; else echo FAIL; fi

printf 'Xray service:  '
if systemctl is-active --quiet xray; then echo OK; else echo FAIL; fi

printf 'Xray port:     '
if ss -ltnp | grep -F "127.0.0.1:$XHTTP_LOCAL_PORT" >/dev/null; then echo OK; else echo FAIL; fi

printf 'HTTPS site:    '
if curl -fsSI "https://$DOMAIN" >/dev/null; then echo OK; else echo FAIL; fi

printf 'Certificate:   '
if test -s /etc/ssl/xray/private.key && test -s /etc/ssl/xray/fullchain.cer; then echo OK; else echo FAIL; fi

printf 'Renewal cron:  '
if crontab -l 2>/dev/null | grep -E 'acme\.sh.*--cron' >/dev/null; then echo OK; else echo FAIL; fi

printf 'Client link:   '
if test -s /root/xray-client-link.txt; then echo OK; else echo FAIL; fi
```

Ожидаемый результат:

```text
Nginx config:  OK
Nginx service: OK
Cron service:  OK
Xray service:  OK
Xray port:     OK
HTTPS site:    OK
Certificate:   OK
Renewal cron:  OK
Client link:   OK
```

Показать клиентскую ссылку:

```bash
cat /root/xray-client-link.txt
```

Если клиент подключается и сайты открываются, настройка завершена.

---

## 15. Возможные ошибки

### Nginx сообщает об устаревшей директиве HTTP/2

Предупреждение:

```text
the "listen ... http2" directive is deprecated
```

В конфигурации должно быть:

```nginx
listen 443 ssl;
http2 on;
```

Не используйте:

```nginx
listen 443 ssl http2;
```

### Nginx сообщает `invalid port in upstream`

Ошибка:

```text
invalid port in upstream "127.0.0.1:"
```

Причина: переменная `XHTTP_LOCAL_PORT` была пустой во время создания конфигурации.

Проверьте:

```bash
cat /root/xray-xhttp-values.env
```

Должны быть заполнены:

```text
XHTTP_LOCAL_PORT="8443"
XHTTP_PATH="/..."
USER_UUID="..."
```

После исправления заново выполните шаги 11–13.

### HTTPS возвращает `502`

Это означает, что Nginx не может подключиться к Xray.

Проверьте:

```bash
systemctl status xray --no-pager -l
journalctl -u xray -n 50 --no-pager
ss -ltnp | grep '127.0.0.1:8443'
```

Xray должен иметь статус `active`, а порт `127.0.0.1:8443` должен прослушиваться.

### Команда `xray` не найдена

Сообщение:

```text
xray: command not found
```

Означает, что шаг установки Xray не был выполнен или завершился ошибкой.

Вернитесь к шагу 9.

### Let's Encrypt сообщает о лимите

Сообщения:

```text
rateLimited
too many certificates
```

Используйте другой домен или дождитесь времени `retry after`, указанного в сообщении Let's Encrypt.

Повторные запуски до этого времени не помогут.

---

## 16. Важные файлы

| Файл | Назначение |
|---|---|
| `/root/xray-xhttp-values.env` | домен, локальный порт, XHTTP path и UUID |
| `/root/xray-client-link.txt` | клиентская VLESS-ссылка |
| `/usr/local/etc/xray/config.json` | конфигурация Xray |
| `/etc/nginx/sites-available/xray-xhttp.conf` | активная конфигурация Nginx |
| `/etc/nginx/sites-available/xray-xhttp.conf.bak` | резервная копия Nginx-конфига |
| `/etc/ssl/xray/private.key` | приватный ключ TLS |
| `/etc/ssl/xray/fullchain.cer` | полная цепочка TLS-сертификата |
| `/root/.acme.sh` | acme.sh и данные автоматического продления |

---

## Коротко о логике

Nginx принимает HTTP и HTTPS-подключения на портах `80` и `443`.

Обычные запросы открывают веб-страницу.

Запросы с сохранённым XHTTP path передаются на локальный адрес:

```text
127.0.0.1:8443
```

Xray напрямую наружу не открыт.

Параметр `mode` в базовой конфигурации и клиентской ссылке не задаётся.
