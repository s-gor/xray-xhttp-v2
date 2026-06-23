#!/usr/bin/env bash

set -Eeuo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
    echo "Ошибка: запустите скрипт от root." >&2
    exit 1
fi

for command_name in systemctl curl apt-get dpkg-query crontab mktemp; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "Ошибка: не найдена обязательная команда: $command_name" >&2
        exit 1
    fi
done

VALUES_FILE="/root/xray-xhttp-values.env"
CLIENT_LINK_FILE="/root/xray-client-link.txt"
INSTALL_LOG="/root/xray-xhttp-install.log"
REMOVE_LOG="/root/xray-xhttp-remove-all.log"

XRAY_INSTALLER_URL="https://github.com/XTLS/Xray-install/raw/main/install-release.sh"

NGINX_DIR="/etc/nginx"
CERT_DIR="/etc/ssl/xray"
WEB_PAGE="/var/www/html/index.html"
ACME_HOME="/root/.acme.sh"

exec > >(tee -a "$REMOVE_LOG") 2>&1

trap 'echo; echo "Ошибка на строке $LINENO. Удаление остановлено. Журнал: $REMOVE_LOG" >&2' ERR

step() {
    printf '\n============================================================\n%s\n============================================================\n' "$1"
}

DOMAIN=""
if [[ -f "$VALUES_FILE" ]]; then
    DOMAIN="$(sed -n 's/^DOMAIN="\([^"]*\)"$/\1/p' "$VALUES_FILE" | head -n 1)"
fi

echo
echo "Этот скрипт полностью удалит установку Xray + XHTTP:"
echo
echo "  - Xray, его службу, конфигурацию, данные и журналы;"
echo "  - Nginx, его пакеты, конфигурацию и журналы;"
echo "  - acme.sh, его cron-задание, сертификаты и каталог;"
echo "  - сертификаты из /etc/ssl/xray;"
echo "  - рабочие файлы, ссылку и журнал установки;"
echo "  - веб-страницу, если она создана нашим установщиком."
echo
echo "ВАЖНО:"
echo
echo "  - будут удалены ВСЕ пакеты и конфигурации Nginx на этом сервере;"
echo "  - будут удалены ВСЕ сертификаты и настройки из /root/.acme.sh;"
echo "  - если Nginx или acme.sh используются другими проектами, они тоже перестанут работать;"
echo "  - чужие файлы в /var/www не удаляются, но без Nginx обслуживаться не будут."
echo
echo "Скрипт НЕ удаляет:"
echo
echo "  - SSH и его настройки;"
echo "  - сеть, firewall и Security Group;"
echo "  - cron как системную службу;"
echo "  - curl, wget, openssl, ca-certificates и другие общие пакеты."
echo
echo "apt autoremove запускаться НЕ будет."
echo "Перед удалением будет создана резервная копия."
echo

read -r -p 'Для продолжения введите DELETE ALL: ' CONFIRM

if [[ "$CONFIRM" != "DELETE ALL" ]]; then
    echo "Удаление отменено."
    exit 0
fi

BACKUP_DIR="/root/xray-xhttp-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -m 700 -p "$BACKUP_DIR"

backup_item() {
    local src="$1"

    if [[ -e "$src" || -L "$src" ]]; then
        mkdir -p "$BACKUP_DIR$(dirname "$src")"
        cp -a "$src" "$BACKUP_DIR$src"
    fi
}

step "1. Создание резервной копии"

for item in \
    "$VALUES_FILE" \
    "${VALUES_FILE}.bak" \
    "$CLIENT_LINK_FILE" \
    "${CLIENT_LINK_FILE}.before-mode-test" \
    "$INSTALL_LOG" \
    "/usr/local/bin/xray" \
    "/usr/local/etc/xray" \
    "/usr/local/share/xray" \
    "/var/log/xray" \
    "/etc/systemd/system/xray.service" \
    "/etc/systemd/system/xray@.service" \
    "/etc/systemd/system/xray.service.d" \
    "/etc/systemd/system/xray@.service.d" \
    "/etc/logrotate.d/xray" \
    "$NGINX_DIR" \
    "/var/log/nginx" \
    "/var/lib/nginx" \
    "$CERT_DIR" \
    "$ACME_HOME" \
    "$WEB_PAGE"; do
    backup_item "$item"
done

if command -v dpkg-query >/dev/null 2>&1; then
    dpkg-query -W -f='${binary:Package}\t${Status}\n' 'nginx*' 'libnginx-mod-*' \
        > "$BACKUP_DIR/nginx-packages.txt" 2>/dev/null || true
fi

echo "Резервная копия: $BACKUP_DIR"

step "2. Остановка служб"

systemctl stop xray 2>/dev/null || true
systemctl disable xray 2>/dev/null || true

systemctl stop nginx 2>/dev/null || true
systemctl disable nginx 2>/dev/null || true

step "3. Полное удаление Xray"

XRAY_REMOVED="no"
TMP_XRAY_INSTALLER="$(mktemp)"

if curl -fsSL "$XRAY_INSTALLER_URL" -o "$TMP_XRAY_INSTALLER"; then
    chmod 700 "$TMP_XRAY_INSTALLER"

    if bash "$TMP_XRAY_INSTALLER" remove --purge; then
        XRAY_REMOVED="yes"
    else
        echo "Официальный удалитель Xray завершился с ошибкой. Выполняется безопасная очистка известных файлов."
    fi
else
    echo "Не удалось загрузить официальный удалитель Xray. Выполняется безопасная очистка известных файлов."
fi

rm -f -- "$TMP_XRAY_INSTALLER"

# Дополнительная очистка на случай неполного удаления.
rm -rf -- \
    /usr/local/bin/xray \
    /usr/local/etc/xray \
    /usr/local/share/xray \
    /var/log/xray \
    /etc/systemd/system/xray.service \
    /etc/systemd/system/xray@.service \
    /etc/systemd/system/xray.service.d \
    /etc/systemd/system/xray@.service.d

rm -f -- \
    /etc/logrotate.d/xray \
    /etc/systemd/system/multi-user.target.wants/xray.service \
    /etc/systemd/system/multi-user.target.wants/xray@.service

systemctl daemon-reload
systemctl reset-failed xray 2>/dev/null || true

if [[ "$XRAY_REMOVED" == "yes" ]]; then
    echo "Xray удалён официальным установщиком."
else
    echo "Xray удалён очисткой известных файлов."
fi

step "4. Полное удаление acme.sh и сертификатов"

if [[ -x "$ACME_HOME/acme.sh" ]]; then
    "$ACME_HOME/acme.sh" --uninstall || true
fi

# Удаляем оставшееся cron-задание acme.sh, если uninstall его не убрал.
if crontab -l >/tmp/xray-xhttp-root-crontab 2>/dev/null; then
    grep -v '/\.acme\.sh/acme\.sh' /tmp/xray-xhttp-root-crontab \
        > /tmp/xray-xhttp-root-crontab.new || true

    if [[ -s /tmp/xray-xhttp-root-crontab.new ]]; then
        crontab /tmp/xray-xhttp-root-crontab.new
    else
        crontab -r 2>/dev/null || true
    fi
fi

rm -f -- /tmp/xray-xhttp-root-crontab /tmp/xray-xhttp-root-crontab.new

for profile in /root/.bashrc /root/.profile /root/.bash_profile /root/.zshrc; do
    if [[ -f "$profile" ]]; then
        sed -i '\|/root/\.acme\.sh/acme\.sh\.env|d' "$profile"
        sed -i '\|\.acme\.sh/acme\.sh\.env|d' "$profile"
    fi
done

rm -rf -- "$ACME_HOME" "$CERT_DIR"

step "5. Удаление Nginx"

mapfile -t NGINX_PACKAGES < <(
    dpkg-query -W -f='${binary:Package}\t${db:Status-Abbrev}\n' \
        'nginx*' 'libnginx-mod-*' 2>/dev/null \
        | awk -F '\t' '$2 ~ /^ii/ {print $1}' \
        | sort -u
)

if [[ "${#NGINX_PACKAGES[@]}" -gt 0 ]]; then
    export DEBIAN_FRONTEND=noninteractive
    echo "Удаляются пакеты: ${NGINX_PACKAGES[*]}"
    apt-get purge -y "${NGINX_PACKAGES[@]}"
else
    echo "Установленные пакеты Nginx не найдены."
fi

rm -rf -- \
    /etc/nginx \
    /var/log/nginx \
    /var/lib/nginx \
    /var/cache/nginx

rm -f -- /run/nginx.pid

systemctl daemon-reload
systemctl reset-failed nginx 2>/dev/null || true

step "6. Удаление страницы установщика"

if [[ -f "$WEB_PAGE" ]]; then
    if grep -Fq "This site is online." "$WEB_PAGE" \
        && grep -Fq "Status: <code>ok</code>" "$WEB_PAGE"; then
        if [[ -z "$DOMAIN" ]] || grep -Fq "<h1>$DOMAIN</h1>" "$WEB_PAGE"; then
            rm -f -- "$WEB_PAGE"
            echo "Страница установщика удалена."
        else
            echo "Страница не совпадает с доменом из рабочего файла и оставлена."
        fi
    else
        echo "Файл $WEB_PAGE не похож на страницу установщика и оставлен."
    fi
fi

rmdir /var/www/html 2>/dev/null || true
rmdir /var/www 2>/dev/null || true

step "7. Удаление рабочих файлов проекта"

rm -f -- \
    "$VALUES_FILE" \
    "${VALUES_FILE}.bak" \
    "$CLIENT_LINK_FILE" \
    "${CLIENT_LINK_FILE}.before-mode-test" \
    "$INSTALL_LOG" \
    /root/xray-keys.txt \
    /root/xray-client-link.txt.bak

step "8. Итоговая проверка"

if command -v xray >/dev/null 2>&1; then
    echo "ПРЕДУПРЕЖДЕНИЕ: команда xray всё ещё найдена: $(command -v xray)"
else
    echo "OK: Xray удалён."
fi

if systemctl cat xray.service >/dev/null 2>&1; then
    echo "ПРЕДУПРЕЖДЕНИЕ: служба xray.service всё ещё зарегистрирована."
else
    echo "OK: служба Xray удалена."
fi

if command -v nginx >/dev/null 2>&1; then
    echo "ПРЕДУПРЕЖДЕНИЕ: команда nginx всё ещё найдена: $(command -v nginx)"
else
    echo "OK: Nginx удалён."
fi

if [[ -d /etc/nginx ]]; then
    echo "ПРЕДУПРЕЖДЕНИЕ: каталог /etc/nginx всё ещё существует."
else
    echo "OK: конфигурация Nginx удалена."
fi

if [[ -d "$ACME_HOME" ]]; then
    echo "ПРЕДУПРЕЖДЕНИЕ: каталог $ACME_HOME всё ещё существует."
else
    echo "OK: acme.sh удалён."
fi

if crontab -l 2>/dev/null | grep -q '/\.acme\.sh/acme\.sh'; then
    echo "ПРЕДУПРЕЖДЕНИЕ: cron-задание acme.sh всё ещё найдено."
else
    echo "OK: cron-задание acme.sh удалено."
fi

printf 'cron: '
systemctl is-active cron 2>/dev/null || true

if systemctl is-active --quiet ssh 2>/dev/null; then
    echo "ssh: active"
elif systemctl is-active --quiet sshd 2>/dev/null; then
    echo "sshd: active"
else
    echo "ssh: статус не определён, настройки SSH не изменялись"
fi

printf '\nПолное удаление завершено.\n'
printf 'Резервная копия: %s\n' "$BACKUP_DIR"
printf 'Журнал удаления: %s\n\n' "$REMOVE_LOG"
printf 'Удалены Xray, Nginx, acme.sh, сертификаты и файлы проекта.\n'
printf 'apt autoremove не запускался.\n'
printf 'SSH, сеть, firewall, cron и общие системные пакеты не изменялись.\n\n'
printf 'Скрипт завершил работу. Должно появиться обычное приглашение оболочки.\n'
printf 'Если вместо него терминал показывает только символ >, нажмите Ctrl+C.\n'
printf 'Повторно запускать скрипт в этом случае не нужно.\n'

