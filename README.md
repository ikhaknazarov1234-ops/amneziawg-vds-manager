# AmneziaWG VDS Manager

Интерактивный bash-скрипт для установки и управления AmneziaWG на Debian/Ubuntu VDS.

Скрипт рассчитан на схему, где VDS выступает центральным VPN-сервером, а ПК, ноутбуки и телефоны подключаются к нему как клиенты и получают внутренние VPN-IP.

## Версия

```text
v2.0
```

В версии `v2.0` добавлена отправка клиентских `.conf` файлов на e-mail через внешний SMTP.

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
- отправка клиентского `.conf` файла на e-mail через внешний SMTP;
- включение IPv4 forwarding;
- NAT через `iptables`;
- режимы клиента:
  - только VPN-сетка `10.66.0.0/24`;
  - весь интернет через VDS.

<img width="669" height="501" alt="image" src="https://github.com/user-attachments/assets/261a790a-4c12-4e91-84ca-5c57d44fa519" />

## Быстрый запуск

```bash
curl -fsSL https://raw.githubusercontent.com/ikhaknazarov1234-ops/amneziawg-vds-manager/main/amneziawg-vds-manager.sh -o amneziawg-vds-manager.sh
chmod +x amneziawg-vds-manager.sh
sudo bash amneziawg-vds-manager.sh
```

## Проверка перед запуском

На свежей VDS с Debian 13:

```bash
apt update
apt install -y curl ca-certificates

rm -f amneziawg-vds-manager.sh

curl -fsSL "https://raw.githubusercontent.com/ikhaknazarov1234-ops/amneziawg-vds-manager/main/amneziawg-vds-manager.sh?cache=$(date +%s)" -o amneziawg-vds-manager.sh

chmod +x amneziawg-vds-manager.sh

bash -n amneziawg-vds-manager.sh && echo "OK"

grep -n "resolvconf\|apt-key\|software-properties-common\|python3-launchpadlib" amneziawg-vds-manager.sh
```

Результат должен быть:

```text
OK
```

<img width="561" height="61" alt="image" src="https://github.com/user-attachments/assets/27da56ec-27ee-4004-9798-54c4450f7249" />


После `grep` вывода быть не должно.

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

Если клиент не подключается и на сервере нет входящих UDP-пакетов, сначала проверь firewall/security group у провайдера.

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

В этом режиме устройства видят друг друга по адресам `10.66.0.x`, но весь интернет клиента не идёт через VDS.

Если нужно, чтобы весь интернет клиента шёл через VDS, выбирай:

```text
2) Весь интернет через VDS
```

## Важное правило для клиентов

Один клиентский конфиг предназначен только для одного устройства.

Правильно:

```text
phone1     отдельный конфиг
notebook1  отдельный конфиг
pc1        отдельный конфиг
```

Неправильно: использовать один и тот же `.conf` на телефоне и ноутбуке одновременно.

Если один конфиг используется на нескольких устройствах, будут конфликтовать ключи, VPN-IP и endpoint. Из-за этого подключение может работать нестабильно.

Для каждого нового устройства создавай нового клиента через меню:

```text
3) Создать клиента
```

## Как скачать конфиг на Windows

Через PowerShell:

```powershell
scp root@SERVER_IP:/root/amneziawg-clients/ИМЯ_КОНФИГА.conf .\ИМЯ_КОНФИГА.conf
```

Пример:

```powershell
scp root@SERVER_IP:/root/amneziawg-clients/pc1.conf .\pc1.conf
```

Если SSH недоступен, можно вывести конфиг в консоль VDS:

```bash
cat /root/amneziawg-clients/ИМЯ_КОНФИГА.conf
```

И сохранить его на ПК как:

```text
ИМЯ_КОНФИГА.conf
```

## Отправка конфига на e-mail

В версии `v2.0` добавлена отправка клиентских `.conf` файлов на e-mail через внешний SMTP.

В меню доступны пункты:

```text
9) Настроить SMTP для отправки конфигов
10) Отправить конфиг клиента на e-mail
```
SMTP настраивается отдельно на каждой VDS. Настройки сохраняются локально на сервере:

```text
/etc/msmtprc
/etc/amneziawg-vds-manager-mail.pass
/root/.muttrc
```

Для отправки через Gmail нужно использовать пароль приложения, а не обычный пароль от аккаунта.

<img width="1798" height="733" alt="image" src="https://github.com/user-attachments/assets/2d927cc9-69ce-4482-8ab0-d1d12e93621b" />
Google App Password


Пример настроек Gmail:

```text
SMTP host: smtp.gmail.com
SMTP port: 587
SMTP user / login: yourname@gmail.com
From e-mail: yourname@gmail.com
SMTP password / app password: пароль приложения Google
```

Сначала настрой SMTP через пункт:

```text
9) Настроить SMTP для отправки конфигов
```

После этого можно отправить клиентский конфиг через пункт:

```text
10) Отправить конфиг клиента на e-mail
```

Клиентский `.conf` содержит приватный ключ. Отправляй его только владельцу устройства.

Для каждого нового устройства создавай отдельный клиентский конфиг.

Если письмо не пришло во входящие, проверь:

```text
Входящие
Спам
Промоакции / Рассылки
```

Отправка напрямую с VDS без внешнего SMTP не используется и не рекомендуется: письма могут попадать в спам или отклоняться почтовыми сервисами.

## Какой клиент использовать

Нужен клиент с поддержкой AmneziaWG, например AmneziaVPN / AmneziaWG.

Обычный WireGuard-клиент может не принять конфиг, потому что в нём есть параметры AmneziaWG:

```text
Jc, Jmin, Jmax, S1, S2, S3, S4, H1, H2, H3, H4
```

## Проверка работы

На сервере:

```bash
sudo awg show awg0
```

У подключённых клиентов должны быть строки:

```text
latest handshake: ...
transfer: ... received, ... sent
```

Проверка с сервера до клиентов:

```bash
ping -c 4 10.66.0.2
ping -c 4 10.66.0.3
```

Проверка с клиента до сервера:

```bash
ping 10.66.0.1
```

Проверка между клиентами:

```bash
ping 10.66.0.2
ping 10.66.0.3
```

Если сервер пингует клиентов, клиенты пингуют сервер, и клиенты пингуют друг друга по адресам `10.66.0.x`, VPN-сетка работает.

## Диагностика UDP

На сервере можно посмотреть входящие пакеты:

```bash
sudo tcpdump -ni any udp port 51820
```

Если при попытке подключения клиента пакетов нет, проблема обычно не в скрипте, а в доступности UDP-порта.

Проверь:

```text
51820/UDP открыт у провайдера
в клиентском конфиге правильный Endpoint
клиент импортирован в AmneziaVPN / AmneziaWG
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

curl -fsSL "https://raw.githubusercontent.com/ikhaknazarov1234-ops/amneziawg-vds-manager/main/amneziawg-vds-manager.sh?cache=$(date +%s)" -o amneziawg-vds-manager.sh

chmod +x amneziawg-vds-manager.sh
bash -n amneziawg-vds-manager.sh && echo "OK"
sudo bash amneziawg-vds-manager.sh
```

Проверка, что скачалась исправленная версия:

```bash
grep -n "resolvconf\|apt-key\|software-properties-common\|python3-launchpadlib" amneziawg-vds-manager.sh
```

В исправленной версии эти слова не должны находиться в основной установке зависимостей.

## Удаление

Через меню:

```text
2) Удалить AmneziaWG
```

Скрипт удалит серверные конфиги и клиентские файлы после подтверждения.

## Важно

Не загружай клиентские `.conf` файлы на GitHub и не отправляй их в общие чаты. Внутри находится приватный ключ клиента.

Отправка `.conf` на e-mail удобна, но это всё равно передача приватного ключа. Если письмо или конфиг могли быть скомпрометированы, удали клиента через меню и создай новый конфиг.
