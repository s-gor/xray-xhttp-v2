## Автоматическая установка одной командой

Запустите скрипт одной из команд ниже.

Когда появится запрос, введите свой домен без `http://` и `https://`.

Пример:

```text
secure-vpn.dynu.net
```

После ввода домена установка продолжится автоматически.

### Если вы вошли под обычным пользователем

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/s-gor/xray-xhttp-v2/main/scripts/install-fixed-final.sh)"
```

### Если вы уже вошли под root

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/s-gor/xray-xhttp-v2/main/scripts/install-fixed-final.sh)"
```

