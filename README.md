# Xray + XHTTP + Nginx + Let's Encrypt

![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04%20%7C%2026.04-E95420?logo=ubuntu\&logoColor=white)
![Nginx](https://img.shields.io/badge/Nginx-reverse%20proxy-009639?logo=nginx\&logoColor=white)
![Xray](https://img.shields.io/badge/Xray-XHTTP-2F80ED)
![Let's Encrypt](https://img.shields.io/badge/Let's%20Encrypt-TLS-003A70?logo=letsencrypt\&logoColor=white)

Пошаговая настройка Xray XHTTP за Nginx с TLS-сертификатом Let's Encrypt.

Инструкция повторно проверена на чистом сервере.

Итоговая схема:

```text
Client -> domain:443 -> Nginx -> 127.0.0.1:8443 -> Xray XHTTP
```

Снаружи открыты только:

```text
80/tcp
443/tcp
```

Xray слушает только локально:

```text
127.0.0.1:8443
```

Порт `8443/tcp` наружу открывать не нужно.

---

## Что изменилось после повторной проверки

По сравнению с первой версией инструкции внесены следующие изменения:

* Установка необходимых пакетов перенесена в начало инструкции — до сохранения и проверки домена.
* В список пакетов добавлен `cron`, необходимый для автоматического запуска проверки и продления сертификатов `acme.sh`.
* Добавлены проверки работы службы `cron` и наличия задания `acme.sh` в `crontab`.
* В команде установки сертификата используется полный путь к `systemctl`:

```bash
--reloadcmd "/usr/bin/systemctl reload nginx"
```

* Уточнена работа режима XHTTP: параметр `mode` в базовой конфигурации явно не задаётся. Используется стандартное автоматическое поведение XHTTP.
* Параметр `mode` не добавляется в клиентскую ссылку.
* Стандартная страница `Bitrate Reference` заменена нейтральной страницей с доменом сервера.
* Сохранены пошаговая структура, проверки после важных действий и ожидаемые результаты команд.

> [!NOTE]
> Настройка и сравнение режимов `packet-up`, `stream-up` и `stream-one` будут вынесены в отдельную инструкцию после отдельного тестирования.
>
> В основном гайде используется стандартное поведение XHTTP без явного указания `mode`.

---

## Для кого этот гайд

Этот гайд не самый короткий. Он рассчитан на людей, которые хотят не только выполнить команды, но и понимать последовательность настройки.

После каждого важного действия показано:

* зачем выполняется этот этап;
* какую команду запускать;
* что должно быть видно при успешном результате;
* где находятся созданные файлы.

Если вы уже опытный администратор, часть пояснений может показаться очевидной.

Если вы только разбираетесь с Linux, Nginx, TLS-сертификатами или Xray, выполняйте этапы по порядку и не пропускайте проверки.

---

## Как выполнять команды

Все команды выполняются на сервере от `root`.

Короткие команды можно копировать и выполнять целиком.

Большие блоки с `cat <<EOF` создают конфигурационные файлы. Такие блоки необходимо копировать полностью, включая последнюю строку `EOF`.

В инструкции не используется `nano`.

Домен, локальный порт, XHTTP path и UUID сохраняются в рабочем файле:

```text
/root/xray-xhttp-values.env
```

После этого значения автоматически подставляются в конфигурацию Xray, конфигурацию Nginx и клиентскую ссылку.

---

## Содержание

1. Требования
2. Обновить сервер и установить пакеты
3. Запустить Nginx и cron
4. Указать домен
5. Проверить DNS и HTTP
6. Создать веб-страницу
7. Выпустить TLS-сертификат
8. Настроить Nginx на HTTPS
9. Установить Xray
10. Создать рабочие значения Xray
11. Создать `config.json`
12. Добавить XHTTP location в Nginx
13. Создать клиентскую ссылку
14. Финальная проверка
15. Важные файлы

---

## 1. Требования

Нужен сервер с Ubuntu Server 24.04 LTS, Ubuntu Server 26.04 LTS или другой совместимой Ubuntu/Debian-системой.

Также нужен домен или DDNS-адрес, который указывает на внешний IPv4 сервера.

Домен необходим, потому что:

* Let's Encrypt проверяет домен перед выпуском TLS-сертификата;
* Nginx принимает HTTPS-подключение для этого домена;
* клиентская VLESS-ссылка использует домен как адрес сервера, SNI и Host.

На сервере, маршрутизаторе или в Security Group должны быть открыты входящие порты:

| Порт      | Назначение                           |
| --------- | ------------------------------------ |
| `80/tcp`  | HTTP и проверка домена Let's Encrypt |
| `443/tcp` | HTTPS и клиентское подключение       |

Порт `8443/tcp` наружу открывать не нужно.

Он используется только внутри сервера:

```text
Nginx -> 127.0.0.1:8443 -> Xray
```

---

## 2. Обновить сервер и установить пакеты

Сначала обновляем систему:

```bash
apt update && apt upgrade -y
```

Устанавливаем необходимые пакеты:

```bash
apt install -y curl wget unzip tar nginx dnsutils ca-certificates openssl cron
```

Для чего они нужны:

| Пакет             | Назначение                                           |
| ----------------- | ---------------------------------------------------- |
| `curl`, `wget`    | загрузка файлов и проверка HTTP/HTTPS                |
| `unzip`, `tar`    | работа с архивами                                    |
| `nginx`           | HTTPS reverse proxy                                  |
| `dnsutils`        | команда `dig` для проверки DNS                       |
| `ca-certificates` | доверенные корневые сертификаты                      |
| `openssl`         | генерация случайного XHTTP path                      |
| `cron`            | автоматический запуск проверки продления сертификата |

Если часть пакетов уже установлена, это нормально. `apt` оставит их без изменений или обновит до актуальной версии.

---

## 3. Запустить Nginx и cron

Запустить Nginx и добавить его в автозагрузку:

```bash
systemctl enable --now nginx
```

Запустить cron и добавить его в автозагрузку:

```bash
systemctl enable --now cron
```

Проверить Nginx:

```bash
systemctl status nginx --no-pager
```

> [!TIP]
> Правильно, если видно:
>
> ```text
> active (running)
> ```

Проверить cron:

```bash
systemctl status cron --no-pager
```

> [!TIP]
> Правильно, если видно:
>
> ```text
> active (running)
> ```

На некоторых версиях Ubuntu в журнале cron может появиться предупреждение:

```text
Referenced but unset environment variable evaluates to an empty string: EXTRA_OPTS
```

Это предупреждение не мешает работе cron.

Проверить, что Nginx слушает порт `80`:

```bash
ss -tulpn | grep ':80'
```

> [!TIP]
> Правильно, если видна строка с адресом `:80`.

---

## 4. Указать домен

Теперь сохраняем домен, который будет использоваться для всей установки.

Выполните команду:

```bash
bash -c 'read -rp "Enter your domain: " DOMAIN; printf "DOMAIN=\"%s\"\n" "$DOMAIN" > /root/xray-xhttp-values.env; chmod 600 /root/xray-xhttp-values.env; cat /root/xray-xhttp-values.env'
```

Терминал спросит:

```text
Enter your domain:
```

Введите свой домен без `http://`, `https://` и завершающего `/`.

Пример:

```text
example.com
```

> [!TIP]
> Правильно, если после выполнения видно:
>
> ```text
> DOMAIN="example.com"
> ```

Файл создаётся с правами `600`, потому что позднее в нём будут храниться UUID и другие рабочие значения.

---

## 5. Проверить DNS и HTTP

Перед выпуском сертификата нужно убедиться, что домен указывает на этот сервер, а порт `80/tcp` доступен снаружи.

Проверить внешний IPv4 сервера:

```bash
curl -4 ifconfig.me
```

> [!TIP]
> Правильно, если показан внешний IPv4 этого сервера.

Проверить, куда указывает домен:

```bash
bash -c 'source /root/xray-xhttp-values.env; dig +short "$DOMAIN"'
```

> [!TIP]
> Правильно, если показан тот же внешний IPv4 сервера.

Если `dig` возвращает несколько адресов, убедитесь, что нужный домен действительно указывает на этот сервер.

Проверить HTTP:

```bash
bash -c 'source /root/xray-xhttp-values.env; curl -I "http://$DOMAIN"'
```

> [!TIP]
> Правильно, если есть HTTP-ответ, например:
>
> ```text
> HTTP/1.1 200 OK
> ```

Если ответа нет, проверьте:

* DNS-запись домена;
* входящий порт `80/tcp`;
* Security Group или сетевой firewall;
* состояние Nginx.

---

## 6. Создать веб-страницу

Обычные запросы к домену должны открывать обычную веб-страницу.

Xray будет доступен только по отдельному случайному XHTTP path.

Страница ниже использует домен сервера в заголовке. При необходимости позднее замените содержимое `/var/www/html/index.html` на собственную страницу.

Не рекомендуется использовать полностью одинаковую страницу на большом количестве серверов.

Скопируйте весь блок целиком:

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
bash -c 'source /root/xray-xhttp-values.env; curl -I "http://$DOMAIN"'
```

> [!TIP]
> Правильно, если видно:
>
> ```text
> HTTP/1.1 200 OK
> ```

---

## 7. Выпустить TLS-сертификат

TLS-сертификат нужен для HTTPS-подключения на порту `443`.

### Установить acme.sh

```bash
curl https://get.acme.sh | sh
```

Проверить установку:

```bash
/root/.acme.sh/acme.sh --version
```

> [!TIP]
> Правильно, если выводится версия `acme.sh`.

### Выбрать Let's Encrypt

```bash
/root/.acme.sh/acme.sh --set-default-ca --server letsencrypt
```

> [!TIP]
> Правильно, если команда завершается без ошибки.

### Выпустить сертификат

```bash
bash -c 'source /root/xray-xhttp-values.env; /root/.acme.sh/acme.sh --issue -d "$DOMAIN" --webroot /var/www/html'
```

> [!TIP]
> Правильно, если в конце видно сообщение об успешном выпуске сертификата.

### Создать каталог для сертификата

```bash
mkdir -p /etc/ssl/xray
```

### Установить сертификат для Nginx

```bash
bash -c 'source /root/xray-xhttp-values.env; /root/.acme.sh/acme.sh --install-cert -d "$DOMAIN" --key-file /etc/ssl/xray/private.key --fullchain-file /etc/ssl/xray/fullchain.cer --reloadcmd "/usr/bin/systemctl reload nginx"'
```

Проверить файлы:

```bash
ls -l /etc/ssl/xray/
```

> [!TIP]
> Правильно, если видны два файла:
>
> ```text
> private.key
> fullchain.cer
> ```

### Проверить автоматическое продление

Проверить, что `acme.sh` добавил задание в `crontab`:

```bash
crontab -l | grep acme.sh
```

> [!TIP]
> Правильно, если видна строка с запуском `acme.sh`.

Проверить работу cron:

```bash
systemctl is-active cron
```

> [!TIP]
> Правильно:
>
> ```text
> active
> ```

Если сертификат не выпустился, проверьте:

* домен указывает на внешний IPv4 сервера;
* порт `80/tcp` открыт;
* Nginx запущен;
* HTTP-страница домена доступна снаружи.

---

## 8. Настроить Nginx на HTTPS

На этом этапе Nginx начинает обслуживать обычную страницу по HTTPS.

Xray пока не участвует.

Скопируйте весь блок целиком:

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
```

Отключить стандартный сайт Nginx:

```bash
rm -f /etc/nginx/sites-enabled/default
```

Включить новый конфиг:

```bash
ln -sf /etc/nginx/sites-available/xray-xhttp.conf /etc/nginx/sites-enabled/xray-xhttp.conf
```

Проверить конфигурацию:

```bash
nginx -t
```

> [!TIP]
> Правильно, если видно:
>
> ```text
> syntax is ok
> test is successful
> ```

Применить конфигурацию:

```bash
systemctl reload nginx
```

Проверить HTTPS:

```bash
bash -c 'source /root/xray-xhttp-values.env; curl -I "https://$DOMAIN"'
```

> [!TIP]
> Правильно, если есть HTTP-ответ без ошибки сертификата, например:
>
> ```text
> HTTP/2 200
> ```

---

## 9. Установить Xray

Установить Xray официальным установочным скриптом:

```bash
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)"
```

Проверить установленную версию:

```bash
xray version
```

> [!TIP]
> Правильно, если выводится версия Xray.

Xray будет использоваться только как локальный backend за Nginx.

---

## 10. Создать рабочие значения Xray

На этом этапе создаются:

* локальный порт Xray `8443`;
* случайный XHTTP path;
* UUID первого пользователя.

Все значения сохраняются в:

```text
/root/xray-xhttp-values.env
```

> [!NOTE]
> Параметр `mode` в базовой установке не задаётся.
>
> Используется стандартное автоматическое поведение XHTTP.
>
> Сначала рекомендуется проверить базовую конфигурацию. Другие режимы будут разобраны отдельно после тестирования.

> [!WARNING]
> Выполните следующую команду один раз.
>
> Повторный запуск создаст новый XHTTP path и новый UUID.
>
> После повторного запуска потребуется заново создать конфигурацию Xray, конфигурацию Nginx и клиентскую ссылку.

Выполните:

```bash
bash -c 'source /root/xray-xhttp-values.env; XHTTP_LOCAL_PORT="8443"; XHTTP_PATH="/$(openssl rand -hex 8)"; USER_UUID="$(xray uuid)"; printf "DOMAIN=\"%s\"\nXHTTP_LOCAL_PORT=\"%s\"\nXHTTP_PATH=\"%s\"\nUSER_UUID=\"%s\"\n" "$DOMAIN" "$XHTTP_LOCAL_PORT" "$XHTTP_PATH" "$USER_UUID" > /root/xray-xhttp-values.env; chmod 600 /root/xray-xhttp-values.env; cat /root/xray-xhttp-values.env'
```

> [!TIP]
> Правильно, если видны четыре заполненные строки:
>
> ```text
> DOMAIN="example.com"
> XHTTP_LOCAL_PORT="8443"
> XHTTP_PATH="/случайный-путь"
> USER_UUID="uuid-пользователя"
> ```

---

## 11. Создать config.json

Xray будет слушать только локальный адрес:

```text
127.0.0.1:8443
```

UUID, порт и XHTTP path берутся из рабочего файла.

Параметр `mode` намеренно не указан.

Скопируйте весь блок целиком:

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
```

Выставить права:

```bash
chown root:root /usr/local/etc/xray/config.json
chmod 644 /usr/local/etc/xray/config.json
```

Права `644` нужны, чтобы служба Xray могла прочитать конфигурацию.

Проверить конфигурацию:

```bash
xray run -test -config /usr/local/etc/xray/config.json
```

> [!TIP]
> Правильно, если команда завершается без ошибок.
>
> Не должно быть строк:
>
> ```text
> error
> failed
> invalid
> ```

Перезапустить Xray:

```bash
systemctl restart xray
```

Проверить статус:

```bash
systemctl status xray --no-pager
```

> [!TIP]
> Правильно, если видно:
>
> ```text
> active (running)
> ```

Проверить последние логи:

```bash
journalctl -u xray -n 20 --no-pager
```

> [!TIP]
> Правильно, если нет ошибок запуска.

Проверить локальный порт:

```bash
ss -tulpn | grep :8443
```

> [!TIP]
> Правильно, если видно:
>
> ```text
> 127.0.0.1:8443
> ```

---

## 12. Добавить XHTTP location в Nginx

Теперь связываем внешний HTTPS-вход с локальным Xray.

Nginx принимает запросы на случайный XHTTP path и передаёт их на:

```text
127.0.0.1:8443
```

Используется regex-location:

```nginx
location ~ ^/path(/|$)
```

Такой вариант принимает:

```text
/path
/path/
/path/дополнительный-путь
```

Перед изменением создаётся резервная копия действующего конфига Nginx.

Скопируйте весь блок целиком:

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
```

Проверить конфигурацию Nginx:

```bash
nginx -t
```

> [!TIP]
> Правильно, если видно:
>
> ```text
> syntax is ok
> test is successful
> ```

Если проверка завершилась ошибкой, не перезагружайте Nginx.

Вернуть предыдущий конфиг можно командой:

```bash
cp /etc/nginx/sites-available/xray-xhttp.conf.bak /etc/nginx/sites-available/xray-xhttp.conf
```

Если проверка успешна, применить конфигурацию:

```bash
systemctl reload nginx
```

Проверить обычную HTTPS-страницу:

```bash
bash -c 'source /root/xray-xhttp-values.env; curl -I "https://$DOMAIN"'
```

> [!TIP]
> Правильно, если есть HTTP-ответ без ошибки сертификата:
>
> ```text
> HTTP/2 200
> ```

---

## 13. Создать клиентскую ссылку

Клиентская VLESS-ссылка создаётся автоматически из сохранённых значений:

* домена;
* UUID;
* XHTTP path;
* TLS SNI;
* Host.

Параметр `mode` в ссылку не добавляется. Клиент использует стандартное автоматическое поведение XHTTP.

Выполните:

```bash
bash -c 'source /root/xray-xhttp-values.env; ENCODED_PATH="${XHTTP_PATH//\//%2F}"; CLIENT_LINK="vless://${USER_UUID}@${DOMAIN}:443?encryption=none&security=tls&sni=${DOMAIN}&host=${DOMAIN}&type=xhttp&path=${ENCODED_PATH}#${DOMAIN}-xhttp"; echo "$CLIENT_LINK" | tee /root/xray-client-link.txt'
```

Проверить ссылку:

```bash
cat /root/xray-client-link.txt
```

> [!TIP]
> Правильно, если видна строка вида:
>
> ```text
> vless://uuid@domain:443?encryption=none&security=tls&sni=domain&host=domain&type=xhttp&path=%2Fpath#domain-xhttp
> ```

В ссылке должно быть:

```text
type=xhttp
```

Параметра `mode` в ссылке быть не должно.

Импортируйте ссылку в клиент.

Если подключение включается и сайты открываются, основная настройка завершена.

---

## 14. Финальная проверка

Проверить конфигурацию Nginx:

```bash
nginx -t
```

> [!TIP]
> Правильно:
>
> ```text
> syntax is ok
> test is successful
> ```

Проверить Nginx:

```bash
systemctl is-active nginx
```

Проверить cron:

```bash
systemctl is-active cron
```

Проверить Xray:

```bash
systemctl is-active xray
```

> [!TIP]
> Все три команды должны показать:
>
> ```text
> active
> ```

Проверить локальный порт Xray:

```bash
ss -tulpn | grep :8443
```

> [!TIP]
> Правильно, если видно:
>
> ```text
> 127.0.0.1:8443
> ```

Проверить, что Xray не слушает этот порт на всех интерфейсах:

```bash
ss -tulpn | grep '0.0.0.0:8443' || echo "OK: Xray listens only locally"
```

> [!TIP]
> Правильно:
>
> ```text
> OK: Xray listens only locally
> ```

Проверить cron-задачу `acme.sh`:

```bash
crontab -l | grep acme.sh
```

Проверить клиентскую ссылку:

```bash
cat /root/xray-client-link.txt
```

Проверить последние логи Xray:

```bash
journalctl -u xray -n 20 --no-pager
```

Проверить HTTPS:

```bash
bash -c 'source /root/xray-xhttp-values.env; curl -I "https://$DOMAIN"'
```

Установка считается успешной, если:

* конфигурация Nginx проходит проверку;
* Nginx, cron и Xray активны;
* Xray слушает только локальный адрес;
* HTTPS-сайт открывается без ошибки сертификата;
* в `crontab` есть задание `acme.sh`;
* клиентская ссылка импортируется;
* через подключение открываются сайты.

---

## 15. Важные файлы

| Файл                                             | Назначение                               |
| ------------------------------------------------ | ---------------------------------------- |
| `/root/xray-xhttp-values.env`                    | домен, локальный порт, XHTTP path и UUID |
| `/root/xray-client-link.txt`                     | клиентская VLESS-ссылка                  |
| `/usr/local/etc/xray/config.json`                | конфигурация Xray                        |
| `/etc/nginx/sites-available/xray-xhttp.conf`     | активная конфигурация Nginx              |
| `/etc/nginx/sites-available/xray-xhttp.conf.bak` | резервная копия конфигурации Nginx       |
| `/etc/ssl/xray/fullchain.cer`                    | TLS-сертификат                           |
| `/etc/ssl/xray/private.key`                      | приватный ключ TLS-сертификата           |
| `/var/www/html/index.html`                       | обычная веб-страница домена              |

---

## Коротко о логике

Nginx принимает внешний HTTPS-трафик на порту `443`.

Обычные запросы открывают веб-страницу.

Запросы на случайный XHTTP path передаются на локальный Xray:

```text
127.0.0.1:8443
```

Xray напрямую наружу не открыт.

Параметр `mode` в базовой конфигурации не задаётся. Используется стандартное автоматическое поведение XHTTP.

Другие режимы будут рассмотрены в отдельной инструкции после тестирования.
