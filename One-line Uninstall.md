## One-line Uninstall

Запустите скрипт и подтвердите полное удаление, введя:

```text
DELETE ALL
```

Если вы вошли под обычным пользователем:

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/s-gor/xray-xhttp-v2/main/scripts/uninstall.sh)"
```

Если вы уже вошли под `root`:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/s-gor/xray-xhttp-v2/main/scripts/uninstall.sh)"
```

После подтверждения скрипт создаст резервную копию и удалит установку Xray + XHTTP.
