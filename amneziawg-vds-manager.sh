#!/usr/bin/env bash
# AmneziaWG VDS Manager
# Ubuntu/Debian helper for installing/removing AmneziaWG and managing client configs.
# Run as root: sudo bash amneziawg-vds-manager.sh

set -Eeuo pipefail

APP_NAME="AmneziaWG VDS Manager"

AWG_IFACE="awg0"
AWG_DIR="/etc/amnezia/amneziawg"
CLIENT_DIR="/root/amneziawg-clients"
MANAGER_CONF="/etc/amneziawg-vds-manager.conf"
AWG_CONF="$AWG_DIR/$AWG_IFACE.conf"
SERVICE_FILE="/etc/systemd/system/awg-quick@.service"
SYSCTL_CONF="/etc/sysctl.d/99-amneziawg-vds.conf"

DEFAULT_PORT="51820"
DEFAULT_SUBNET="10.66.0.0/24"
DEFAULT_SERVER_IP="10.66.0.1"
DEFAULT_DNS1="1.1.1.1"
DEFAULT_DNS2="8.8.8.8"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err() { echo -e "${RED}[-]${NC} $*"; }
info() { echo -e "${BLUE}[i]${NC} $*"; }

pause() {
  echo
  read -rp "Нажмите Enter для продолжения..." _ || true
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "Запустите скрипт от root: sudo bash $0"
    exit 1
  fi
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

is_supported_os() {
  [[ -r /etc/os-release ]] || return 1
  # shellcheck disable=SC1091
  source /etc/os-release
  case "${ID:-}" in
    ubuntu|debian) return 0 ;;
  esac
  case "${ID_LIKE:-}" in
    *debian*) return 0 ;;
  esac
  return 1
}

require_supported_os() {
  if ! is_supported_os; then
    err "Сейчас поддерживаются только Debian/Ubuntu."
    exit 1
  fi
}

load_vars() {
  if [[ -f "$MANAGER_CONF" ]]; then
    # shellcheck disable=SC1090
    source "$MANAGER_CONF"
  fi

  SERVER_PORT="${SERVER_PORT:-$DEFAULT_PORT}"
  VPN_SUBNET="${VPN_SUBNET:-$DEFAULT_SUBNET}"
  SERVER_VPN_IP="${SERVER_VPN_IP:-$DEFAULT_SERVER_IP}"
  SERVER_PUBLIC_IP="${SERVER_PUBLIC_IP:-}"
  WAN_IFACE="${WAN_IFACE:-}"
  DNS1="${DNS1:-$DEFAULT_DNS1}"
  DNS2="${DNS2:-$DEFAULT_DNS2}"

  AWG_JC="${AWG_JC:-8}"
  AWG_JMIN="${AWG_JMIN:-16}"
  AWG_JMAX="${AWG_JMAX:-80}"
  AWG_S1="${AWG_S1:-64}"
  AWG_S2="${AWG_S2:-128}"
  AWG_S3="${AWG_S3:-0}"
  AWG_S4="${AWG_S4:-0}"
  AWG_H1="${AWG_H1:-11111111}"
  AWG_H2="${AWG_H2:-22222222}"
  AWG_H3="${AWG_H3:-33333333}"
  AWG_H4="${AWG_H4:-44444444}"
}

save_vars() {
  mkdir -p "$(dirname "$MANAGER_CONF")"
  cat > "$MANAGER_CONF" <<EOF
SERVER_PORT="$SERVER_PORT"
VPN_SUBNET="$VPN_SUBNET"
SERVER_VPN_IP="$SERVER_VPN_IP"
SERVER_PUBLIC_IP="$SERVER_PUBLIC_IP"
WAN_IFACE="$WAN_IFACE"
DNS1="$DNS1"
DNS2="$DNS2"
AWG_JC="$AWG_JC"
AWG_JMIN="$AWG_JMIN"
AWG_JMAX="$AWG_JMAX"
AWG_S1="$AWG_S1"
AWG_S2="$AWG_S2"
AWG_S3="$AWG_S3"
AWG_S4="$AWG_S4"
AWG_H1="$AWG_H1"
AWG_H2="$AWG_H2"
AWG_H3="$AWG_H3"
AWG_H4="$AWG_H4"
EOF
  chmod 600 "$MANAGER_CONF"
}

detect_wan_iface() {
  ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++){if($i=="dev"){print $(i+1); exit}}}'
}

detect_public_ip() {
  local ip=""
  ip="$(curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"
  if [[ -z "$ip" ]]; then
    ip="$(curl -4 -fsS --max-time 5 https://ifconfig.me 2>/dev/null || true)"
  fi
  echo "$ip"
}

valid_ip_or_host() {
  [[ "$1" =~ ^[A-Za-z0-9._:-]+$ ]]
}

valid_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( "$1" >= 1 && "$1" <= 65535 ))
}

valid_client_name() {
  [[ "$1" =~ ^[A-Za-z0-9_-]{1,64}$ ]]
}

valid_ipv4_cidr_24() {
  [[ "$1" =~ ^([0-9]{1,3}\.){3}0/24$ ]]
}

installed() {
  [[ -f "$AWG_CONF" ]] && command_exists awg && command_exists awg-quick
}

random_header() {
  shuf -i 10000000-2147483647 -n 1
}

generate_awg_params() {
  AWG_JC="$(shuf -i 4-12 -n 1)"
  AWG_JMIN="$(shuf -i 8-24 -n 1)"
  AWG_JMAX="$(shuf -i 64-128 -n 1)"
  AWG_S1="$(shuf -i 40-120 -n 1)"
  AWG_S2="$(shuf -i 130-220 -n 1)"
  AWG_S3="0"
  AWG_S4="0"

  local h
  declare -A used=()
  for h in 1 2 3 4; do
    local value
    while true; do
      value="$(random_header)"
      [[ -z "${used[$value]:-}" ]] && break
    done
    used[$value]=1
    case "$h" in
      1) AWG_H1="$value" ;;
      2) AWG_H2="$value" ;;
      3) AWG_H3="$value" ;;
      4) AWG_H4="$value" ;;
    esac
  done
}

ask_install_params() {
  load_vars

  local detected_ip detected_iface input
  detected_ip="$(detect_public_ip)"
  detected_iface="$(detect_wan_iface)"

  echo
  info "Параметры AmneziaWG. Можно нажимать Enter для значений по умолчанию."

  read -rp "Публичный IP/домен VDS [${detected_ip:-$SERVER_PUBLIC_IP}]: " input || true
  SERVER_PUBLIC_IP="${input:-${detected_ip:-$SERVER_PUBLIC_IP}}"
  while [[ -z "$SERVER_PUBLIC_IP" ]] || ! valid_ip_or_host "$SERVER_PUBLIC_IP"; do
    read -rp "Введите корректный публичный IP или домен: " SERVER_PUBLIC_IP
  done

  read -rp "UDP-порт AmneziaWG [$DEFAULT_PORT]: " input || true
  SERVER_PORT="${input:-$DEFAULT_PORT}"
  while ! valid_port "$SERVER_PORT"; do
    read -rp "Введите порт 1-65535: " SERVER_PORT
  done

  read -rp "VPN-сеть IPv4 /24 [$DEFAULT_SUBNET]: " input || true
  VPN_SUBNET="${input:-$DEFAULT_SUBNET}"
  while ! valid_ipv4_cidr_24 "$VPN_SUBNET"; do
    read -rp "Введите сеть вида 10.66.0.0/24: " VPN_SUBNET
  done
  SERVER_VPN_IP="${VPN_SUBNET%0/24}1"

  read -rp "Внешний сетевой интерфейс [${detected_iface:-$WAN_IFACE}]: " input || true
  WAN_IFACE="${input:-${detected_iface:-$WAN_IFACE}}"
  while [[ -z "$WAN_IFACE" || ! -d "/sys/class/net/$WAN_IFACE" ]]; do
    read -rp "Интерфейс не найден. Введите внешний интерфейс, например eth0/ens3: " WAN_IFACE
  done

  read -rp "DNS #1 для клиентов [$DEFAULT_DNS1]: " input || true
  DNS1="${input:-$DEFAULT_DNS1}"
  read -rp "DNS #2 для клиентов [$DEFAULT_DNS2]: " input || true
  DNS2="${input:-$DEFAULT_DNS2}"

  generate_awg_params
  save_vars
}

ensure_deb_src_debian() {
  if ! grep -Rqs "ppa.launchpadcontent.net/amnezia/ppa" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
    echo "deb https://ppa.launchpadcontent.net/amnezia/ppa/ubuntu focal main" > /etc/apt/sources.list.d/amnezia-ppa.list
    echo "deb-src https://ppa.launchpadcontent.net/amnezia/ppa/ubuntu focal main" >> /etc/apt/sources.list.d/amnezia-ppa.list
  fi
}

install_amneziawg_packages() {
  require_supported_os

  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg2 software-properties-common python3-launchpadlib \
    iproute2 iptables qrencode resolvconf lsb-release

  if apt-cache show "linux-headers-$(uname -r)" >/dev/null 2>&1; then
    apt-get install -y "linux-headers-$(uname -r)" || warn "Не удалось установить linux-headers для текущего ядра."
  else
    warn "Пакет linux-headers-$(uname -r) не найден. Установка модуля DKMS может не пройти."
  fi

  # shellcheck disable=SC1091
  source /etc/os-release

  if [[ "${ID:-}" == "ubuntu" ]]; then
    log "Добавляю PPA amnezia/ppa..."
    add-apt-repository -y ppa:amnezia/ppa
  else
    log "Добавляю PPA amnezia/ppa для Debian по инструкции AmneziaWG..."
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 57290828 || true
    ensure_deb_src_debian
  fi

  apt-get update
  log "Устанавливаю AmneziaWG..."
  apt-get install -y amneziawg

  if ! command_exists awg || ! command_exists awg-quick; then
    err "После установки не найдены awg/awg-quick. Проверьте вывод apt."
    exit 1
  fi
}

write_systemd_unit() {
  cat > "$SERVICE_FILE" <<'EOF'
[Unit]
Description=AmneziaWG via awg-quick for %i
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
Environment=WG_QUICK_USERSPACE_IMPLEMENTATION=amneziawg-go
ExecStart=/bin/bash -lc 'awg-quick up %i'
ExecStop=/bin/bash -lc 'awg-quick down %i'
ExecReload=/bin/bash -lc 'awg syncconf %i <(awg-quick strip %i)'
Restart=no

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
}

write_sysctl() {
  cat > "$SYSCTL_CONF" <<EOF
net.ipv4.ip_forward=1
EOF
  sysctl --system >/dev/null || true
}

open_ufw_port_if_active() {
  if command_exists ufw && ufw status 2>/dev/null | grep -qi "Status: active"; then
    ufw allow "$SERVER_PORT/udp" || true
    ufw reload || true
  fi
}

server_private_key_file() { echo "$AWG_DIR/server_private.key"; }
server_public_key_file() { echo "$AWG_DIR/server_public.key"; }

create_server_config() {
  mkdir -p "$AWG_DIR" "$CLIENT_DIR"
  chmod 700 "$AWG_DIR" "$CLIENT_DIR"

  local server_private server_public
  server_private="$(awg genkey)"
  server_public="$(echo "$server_private" | awg pubkey)"

  echo "$server_private" > "$(server_private_key_file)"
  echo "$server_public" > "$(server_public_key_file)"
  chmod 600 "$(server_private_key_file)"

  cat > "$AWG_CONF" <<EOF
[Interface]
PrivateKey = $server_private
Address = $SERVER_VPN_IP/24
ListenPort = $SERVER_PORT
Jc = $AWG_JC
Jmin = $AWG_JMIN
Jmax = $AWG_JMAX
S1 = $AWG_S1
S2 = $AWG_S2
S3 = $AWG_S3
S4 = $AWG_S4
H1 = $AWG_H1
H2 = $AWG_H2
H3 = $AWG_H3
H4 = $AWG_H4

PostUp = sysctl -w net.ipv4.ip_forward=1; iptables -A FORWARD -i $AWG_IFACE -j ACCEPT; iptables -A FORWARD -o $AWG_IFACE -j ACCEPT; iptables -t nat -A POSTROUTING -s $VPN_SUBNET -o $WAN_IFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i $AWG_IFACE -j ACCEPT; iptables -D FORWARD -o $AWG_IFACE -j ACCEPT; iptables -t nat -D POSTROUTING -s $VPN_SUBNET -o $WAN_IFACE -j MASQUERADE

EOF

  chmod 600 "$AWG_CONF"
}

start_service() {
  write_systemd_unit
  systemctl enable --now "awg-quick@$AWG_IFACE.service"

  if ! systemctl is-active --quiet "awg-quick@$AWG_IFACE.service"; then
    err "AmneziaWG не запустился. Последние строки журнала:"
    journalctl -u "awg-quick@$AWG_IFACE.service" -n 60 --no-pager || true
    exit 1
  fi
}

install_awg() {
  if installed; then
    warn "AmneziaWG уже установлен через этот скрипт: $AWG_CONF"
    return 0
  fi

  ask_install_params
  install_amneziawg_packages
  write_sysctl
  create_server_config
  open_ufw_port_if_active
  start_service

  log "Установка завершена."
  info "Сервер: $SERVER_PUBLIC_IP:$SERVER_PORT/udp"
  info "VPN-сеть: $VPN_SUBNET, IP сервера: $SERVER_VPN_IP"
  info "Клиентские конфиги: $CLIENT_DIR"
  warn "Если у провайдера есть внешний firewall/security group, откройте $SERVER_PORT/udp."
}

vpn_prefix() {
  echo "${VPN_SUBNET%0/24}"
}

client_ip_for_index() {
  local idx="$1"
  echo "$(vpn_prefix)$idx"
}

used_client_ips() {
  grep -hE '^Address = ' "$CLIENT_DIR"/*.conf 2>/dev/null | awk '{print $3}' | cut -d/ -f1 || true
}

next_client_ip() {
  local used ip i
  used="$(used_client_ips)"
  for i in $(seq 2 254); do
    ip="$(client_ip_for_index "$i")"
    if ! grep -qx "$ip" <<< "$used"; then
      echo "$ip"
      return 0
    fi
  done
  return 1
}

restart_or_reload_awg() {
  if systemctl is-active --quiet "awg-quick@$AWG_IFACE.service"; then
    systemctl restart "awg-quick@$AWG_IFACE.service"
  else
    systemctl start "awg-quick@$AWG_IFACE.service"
  fi
}

client_allowed_ips() {
  echo
  echo "Режим маршрутизации клиента:"
  echo "1) Только VPN-сетка $VPN_SUBNET — устройства видят друг друга по VPN-IP"
  echo "2) Весь интернет через VDS"
  read -rp "Выберите режим [1]: " mode
  mode="${mode:-1}"
  case "$mode" in
    2) echo "0.0.0.0/0" ;;
    *) echo "$VPN_SUBNET" ;;
  esac
}

create_client() {
  if ! installed; then
    err "AmneziaWG ещё не установлен. Сначала выберите пункт установки."
    return 1
  fi

  load_vars

  local name ip allowed private public psk conf server_public
  read -rp "Имя клиента, например pc1 или phone1: " name
  if ! valid_client_name "$name"; then
    err "Имя может содержать только A-Z, a-z, 0-9, _ и -, длина до 64 символов."
    return 1
  fi

  conf="$CLIENT_DIR/$name.conf"
  if [[ -f "$conf" ]]; then
    err "Клиент '$name' уже существует: $conf"
    return 1
  fi

  ip="$(next_client_ip)" || { err "Свободные IP в $VPN_SUBNET закончились."; return 1; }
  allowed="$(client_allowed_ips)"
  private="$(awg genkey)"
  public="$(echo "$private" | awg pubkey)"
  psk="$(awg genpsk)"
  server_public="$(cat "$(server_public_key_file)")"

  cat > "$conf" <<EOF
[Interface]
PrivateKey = $private
Address = $ip/32
DNS = $DNS1, $DNS2
Jc = $AWG_JC
Jmin = $AWG_JMIN
Jmax = $AWG_JMAX
S1 = $AWG_S1
S2 = $AWG_S2
S3 = $AWG_S3
S4 = $AWG_S4
H1 = $AWG_H1
H2 = $AWG_H2
H3 = $AWG_H3
H4 = $AWG_H4

[Peer]
PublicKey = $server_public
PresharedKey = $psk
AllowedIPs = $allowed
Endpoint = $SERVER_PUBLIC_IP:$SERVER_PORT
PersistentKeepalive = 25
EOF
  chmod 600 "$conf"

  cat >> "$AWG_CONF" <<EOF

# BEGIN_CLIENT $name
[Peer]
# Name = $name
PublicKey = $public
PresharedKey = $psk
AllowedIPs = $ip/32
# END_CLIENT $name
EOF

  chmod 600 "$AWG_CONF"
  restart_or_reload_awg

  log "Клиент создан: $name"
  info "VPN IP: $ip"
  info "Конфиг: $conf"
}

remove_client_block() {
  local name="$1"
  awk -v name="$name" '
    $0 == "# BEGIN_CLIENT " name {skip=1; next}
    $0 == "# END_CLIENT " name {skip=0; next}
    skip != 1 {print}
  ' "$AWG_CONF" > "$AWG_CONF.tmp"
  mv "$AWG_CONF.tmp" "$AWG_CONF"
  chmod 600 "$AWG_CONF"
}

delete_client() {
  if ! installed; then
    err "AmneziaWG ещё не установлен."
    return 1
  fi

  local name
  read -rp "Имя клиента для удаления: " name
  if ! valid_client_name "$name"; then
    err "Некорректное имя клиента."
    return 1
  fi

  if [[ ! -f "$CLIENT_DIR/$name.conf" ]] && ! grep -q "^# BEGIN_CLIENT $name$" "$AWG_CONF"; then
    warn "Клиент '$name' не найден."
    return 0
  fi

  read -rp "Точно удалить клиента '$name'? [y/N]: " confirm
  [[ "${confirm,,}" == "y" || "${confirm,,}" == "yes" ]] || { warn "Отменено."; return 0; }

  remove_client_block "$name"
  rm -f "$CLIENT_DIR/$name.conf"
  restart_or_reload_awg

  log "Клиент '$name' удалён."
}

list_clients() {
  if [[ ! -d "$CLIENT_DIR" ]]; then
    warn "Каталог клиентов не найден: $CLIENT_DIR"
    return 0
  fi

  echo
  info "Клиентские конфиги в $CLIENT_DIR:"
  shopt -s nullglob
  local files=("$CLIENT_DIR"/*.conf)
  if (( ${#files[@]} == 0 )); then
    warn "Пока нет созданных клиентов."
  else
    local f
    for f in "${files[@]}"; do
      local addr endpoint allowed
      addr="$(grep -m1 '^Address = ' "$f" | awk '{print $3}' || true)"
      endpoint="$(grep -m1 '^Endpoint = ' "$f" | cut -d= -f2- | xargs || true)"
      allowed="$(grep -m1 '^AllowedIPs = ' "$f" | cut -d= -f2- | xargs || true)"
      echo " - $(basename "$f") | Address=$addr | Endpoint=$endpoint | AllowedIPs=$allowed"
    done
  fi
  shopt -u nullglob
}

show_client() {
  local name conf
  read -rp "Имя клиента: " name
  if ! valid_client_name "$name"; then
    err "Некорректное имя клиента."
    return 1
  fi

  conf="$CLIENT_DIR/$name.conf"
  if [[ ! -f "$conf" ]]; then
    err "Файл не найден: $conf"
    return 1
  fi

  echo
  info "Конфиг клиента: $conf"
  echo "----------------------------------------"
  cat "$conf"
  echo "----------------------------------------"

  if command_exists qrencode; then
    echo
    info "QR-код:"
    qrencode -t ansiutf8 < "$conf"
  else
    warn "qrencode не установлен."
  fi
}

show_status() {
  echo
  info "Статус сервиса:"
  systemctl --no-pager --full status "awg-quick@$AWG_IFACE.service" || true

  echo
  info "Интерфейс:"
  ip addr show "$AWG_IFACE" 2>/dev/null || warn "Интерфейс $AWG_IFACE не найден."

  echo
  info "Peers:"
  awg show "$AWG_IFACE" 2>/dev/null || warn "awg show не сработал."
}

show_logs() {
  journalctl -u "awg-quick@$AWG_IFACE.service" -n 100 --no-pager || true
}

uninstall_awg() {
  echo
  warn "Будут удалены конфиги AmneziaWG, ключи и клиентские файлы."
  warn "Старые клиентские конфиги без резервной копии восстановить нельзя."
  read -rp "Введите DELETE для подтверждения: " confirm
  [[ "$confirm" == "DELETE" ]] || { warn "Отменено."; return 0; }

  systemctl disable --now "awg-quick@$AWG_IFACE.service" 2>/dev/null || true

  rm -f "$SERVICE_FILE" "$SYSCTL_CONF" "$MANAGER_CONF"
  rm -rf "$AWG_DIR" "$CLIENT_DIR"

  systemctl daemon-reload
  sysctl --system >/dev/null || true

  read -rp "Удалить пакет amneziawg через apt purge? [y/N]: " purge
  if [[ "${purge,,}" == "y" || "${purge,,}" == "yes" ]]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get purge -y amneziawg || true
    apt-get autoremove -y || true
  fi

  log "Удаление завершено."
}

print_banner() {
  cat <<'EOF'
    ___                          _       _       __  ________
   /   |  ____ ___  ____  ___  _(_)___ _| |     / / / ____/ /
  / /| | / __ `__ \/ __ \/ _ \/_/ / __ `/ | /| / / / / __/ / 
 / ___ |/ / / / / / / / /  __/ / / /_/ /| |/ |/ / / /_/ /_/  
/_/  |_/_/ /_/ /_/_/ /_/\___/_/ /\__,_/ |__/|__/  \____(_)   
                            /___/                             
              VDS Manager
EOF
}

menu() {
  while true; do
    clear || true
    print_banner
    echo "========================================"
    echo " $APP_NAME"
    echo "========================================"
    echo "1) Установить и настроить AmneziaWG"
    echo "2) Удалить AmneziaWG"
    echo "3) Создать клиента"
    echo "4) Удалить клиента"
    echo "5) Показать список клиентов"
    echo "6) Показать конфиг/QR клиента"
    echo "7) Показать статус"
    echo "8) Показать логи"
    echo "0) Выход"
    echo "----------------------------------------"
    read -rp "Выберите пункт: " choice

    case "$choice" in
      1) install_awg; pause ;;
      2) uninstall_awg; pause ;;
      3) create_client; pause ;;
      4) delete_client; pause ;;
      5) list_clients; pause ;;
      6) show_client; pause ;;
      7) show_status; pause ;;
      8) show_logs; pause ;;
      0) exit 0 ;;
      *) warn "Неверный пункт"; pause ;;
    esac
  done
}

main() {
  require_root
  load_vars
  menu
}

main "$@"
