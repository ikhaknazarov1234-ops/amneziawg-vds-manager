# AmneziaWG VDS Manager

Интерактивный bash-скрипт для установки и управления AmneziaWG на Debian/Ubuntu VDS.

Скрипт рассчитан на схему, где VDS выступает центральным VPN-сервером, а ПК, ноутбуки и телефоны подключаются к нему как клиенты и получают внутренние VPN-IP.

## Схема сети

```text
VDS      10.66.0.1
ПК1      10.66.0.2
ПК2      10.66.0.3
Телефон  10.66.0.4
```

Клиенты могут общаться друг с другом по внутренним VPN-IP через VDS.

## Возможности

- установка и настройка AmneziaWG;
- создание интерфейса `awg0`;
- генерация серверных и клиентских ключей;
- создание клиентских `.conf` файлов;
- удаление клиентов;
- показ клиентского конфига и QR-кода;
- включение IPv4 forwarding;
- NAT через `iptables`;
- режимы клиента:
  - только VPN-сетка `10.66.0.0/24`;
  - весь интернет через VDS.

## Быстрый запуск

```bash
curl -fsSL https://raw.githubusercontent.com/ikhaknazarov1234-ops/amneziawg-vds-manager/main/amneziawg-vds-manager.sh -o amneziawg-vds-manager.sh
chmod +x amneziawg-vds-manager.sh
sudo bash amneziawg-vds-manager.sh
```

## Проверка перед запуском

На свежей VDS с Debian 13

```bash
apt update
apt install -y curl ca-certificates

rm -f amneziawg-vds-manager.sh

curl -fsSL "https://raw.githubusercontent.com/ikhaknazarov1234-ops/amneziawg-vds-manager/main/amneziawg-vds-manager.sh?cache=$(date +%s)" -o amneziawg-vds-manager.sh

chmod +x amneziawg-vds-manager.sh

bash -n amneziawg-vds-manager.sh && echo "OK"

grep -n "resolvconf\|apt-key\|software-properties-common\|python3-launchpadlib" amneziawg-vds-manager.sh
```
Результат должен быть "ОК"
А после grep — пусто

## Поддерживаемые ОС

Проверялось/рассчитано на:

```text
Debian / Ubuntu с systemd и apt
```

На Debian используется PPA AmneziaWG через отдельный keyring:

```text
/etc/apt/keyrings/amnezia-ppa.gpg
/etc/apt/sources.list.d/amnezia-ppa.list
```

Скрипт не должен использовать `apt-key` и не должен ставить `resolvconf`.

## Что открыть у провайдера

По умолчанию AmneziaWG использует UDP-порт:

```text
51820/UDP
```

Если при установке указан другой порт, открой именно его.

Например, если выбрал порт `443`, то открыть нужно:

```text
443/UDP
```

## Где лежат клиентские конфиги

```bash
/root/amneziawg-clients/
```

Пример:

```bash
/root/amneziawg-clients/pc1.conf
```

## Как создать клиента

Запусти скрипт:

```bash
sudo bash amneziawg-vds-manager.sh
```

Выбери пункт:

```text
3) Создать клиента
```

Для обычной внутренней сетки выбирай режим:

```text
1) Только VPN-сетка 10.66.0.0/24
```

Если нужно, чтобы весь интернет клиента шёл через VDS, выбирай:

```text
2) Весь интернет через VDS
```

## Как скачать конфиг на Windows

Через PowerShell:

```powershell
scp root@SERVER_IP:/root/amneziawg-clients/pc1.conf C:\Users\ikhak\Downloads\
```

Если SSH недоступен, можно вывести конфиг в консоль VDS:

```bash
cat /root/amneziawg-clients/pc1.conf
```

И сохранить его на ПК как:

```text
pc1.conf
```

## Какой клиент использовать

Нужен клиент с поддержкой AmneziaWG, например AmneziaVPN / AmneziaWG.

Обычный WireGuard-клиент может не принять конфиг, потому что в нём есть параметры AmneziaWG:

```text
Jc, Jmin, Jmax, S1, S2, S3, S4, H1, H2, H3, H4
```

## Если ранее запускалась старая версия скрипта

Если старая версия успела поставить `resolvconf` или добавить PPA без ключа, можно почистить систему так:

```bash
sudo rm -f /etc/apt/sources.list.d/amnezia-ppa.list
sudo rm -f /etc/apt/keyrings/amnezia-ppa.gpg

sudo systemctl disable --now resolvconf.service resolvconf-pull-resolved.path resolvconf-pull-resolved.service 2>/dev/null || true
sudo apt purge -y resolvconf || true

sudo apt install -y systemd-resolved
sudo systemctl enable --now systemd-resolved
sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

sudo apt update
```

После этого скачай свежий скрипт заново:

```bash
rm -f amneziawg-vds-manager.sh

curl -fsSL https://raw.githubusercontent.com/ikhaknazarov1234-ops/amneziawg-vds-manager/main/amneziawg-vds-manager.sh -o amneziawg-vds-manager.sh

chmod +x amneziawg-vds-manager.sh
bash -n amneziawg-vds-manager.sh && echo "OK"
sudo bash amneziawg-vds-manager.sh
```

Проверка, что скачалась исправленная версия:

```bash
grep -n "resolvconf\|apt-key\|software-properties-common\|python3-launchpadlib" amneziawg-vds-manager.sh
```

В исправленной версии эти слова не должны находиться в основной установке зависимостей.

## Важно

Не загружай клиентские `.conf` файлы на GitHub и не отправляй их в общие чаты. Внутри находится приватный ключ клиента.
