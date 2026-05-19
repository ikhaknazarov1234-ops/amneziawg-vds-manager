# AmneziaWG VDS Manager

Интерактивный bash-скрипт для установки и управления AmneziaWG на Debian.

Пример схемы:

```text
VDS      10.66.0.1
ПК1      10.66.0.2
ПК2      10.66.0.3
Телефон  10.66.0.4
```

Клиенты могут общаться между собой через VDS по адресам `10.66.0.x`.

## Возможности

- установка AmneziaWG userspace-реализации `amneziawg-go`;
- сборка и установка `amneziawg-tools`: `awg`, `awg-quick`;
- создание центрального интерфейса `awg0`;
- генерация клиентов с отдельными ключами и PSK;
- режим клиента:
  - только VPN-сетка `10.66.0.0/24`;
  - весь интернет через VDS;
- удаление клиентов;
- вывод конфига и QR-кода;
- NAT и forwarding через `iptables`;
- управление через `systemd`.

## Поддержка

Скрипт рассчитан на Debian подобные системы с `systemd` и `apt`.

## Установка и запуск

```bash
curl -fsSL https://raw.githubusercontent.com/USER/amneziawg-vds-manager/main/amneziawg-vds-manager.sh -o amneziawg-vds-manager.sh
chmod +x amneziawg-vds-manager.sh
sudo bash amneziawg-vds-manager.sh
```

Замените `USER` на свой GitHub username.

## Меню

```text
1) Установить и настроить AmneziaWG
2) Удалить AmneziaWG
3) Создать клиента
4) Удалить клиента
5) Показать список клиентов
6) Показать конфиг/QR клиента
7) Показать статус
8) Показать логи
0) Выход
```

## Где лежат клиентские конфиги

```bash
/root/amneziawg-clients/<client>.conf
```

Например:

```bash
/root/amneziawg-clients/phone1.conf
```

Файл можно импортировать в клиент, поддерживающий AmneziaWG.

## Клиенты

Для телефона/ПК удобнее использовать официальный клиент Amnezia VPN или совместимый клиент с поддержкой AmneziaWG.

Обычный WireGuard-клиент может не подойти, потому что AmneziaWG использует дополнительные параметры обфускации:

```text
Jc, Jmin, Jmax, S1, S2, S3, S4, H1, H2, H3, H4
```

## Как скачать конфиг на Windows

Если SSH/SCP работает:

```powershell
scp root@SERVER_IP:/root/amneziawg-clients/phone1.conf C:\Users\USER\Downloads\
```

Если SCP не работает, можно вывести файл текстом:

```bash
cat /root/amneziawg-clients/phone1.conf
```

И сохранить содержимое на ПК как `phone1.conf`.

## Важно

Клиентские `.conf` содержат приватные ключи.
