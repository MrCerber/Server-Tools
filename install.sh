#!/usr/bin/env bash
# MrCerber - New Server Bootstrap (Ubuntu/Debian)
# Requirements:
# - MUST be run as root
# - SSH keys already installed for root (assumed)
# - NO user creation, NO timezone changes, NO swap changes
#
# Features:
# - Interactive main menu + sub menus (UFW / Fail2ban)
# - Base packages install
# - Automatic security updates (unattended-upgrades)
# - Disable default MOTD + disable SSH "Last login"
# - Install custom MOTD from two files: 99-mrcerber and logo.txt
# - Restore default MOTD + restore "Last login"
# - Install useful shell aliases (bench, geoip)
# - OS version check, internet connectivity check, action logging
#
# How custom MOTD works:
# Place your custom files next to this script:
# ./99-mrcerber
# ./logo.txt
# Script installs them into:
# /etc/update-motd.d/99-mrcerber
# /etc/update-motd.d/logo.txt

set -Eeuo pipefail

# ---------------------------
# Globals
# ---------------------------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
CUSTOM_MOTD_99_SRC="${SCRIPT_DIR}/99-mrcerber"
CUSTOM_MOTD_LOGO_SRC="${SCRIPT_DIR}/logo.txt"
MOTD_BASE_URL="${MOTD_BASE_URL:-https://raw.githubusercontent.com/MrCerber/Server-Tools/refs/heads/main}"

MOTD_DIR="/etc/update-motd.d"
BACKUP_DIR="/root/.mrcerber-bootstrap-backups"
SSHD_CONFIG="/etc/ssh/sshd_config"
LOG_FILE="/root/.mrcerber-bootstrap.log"
ALIASES_BASHRC="/root/.bashrc"

# ---------------------------
# Colors
# ---------------------------
R=$'\e[0m'
BOLD=$'\e[1m'
C_TITLE=$'\e[38;5;45m'
C_NUM=$'\e[38;5;214m'
C_OK=$'\e[38;5;82m'
C_WARN=$'\e[38;5;220m'
C_ERR=$'\e[38;5;196m'
C_DIM=$'\e[38;5;240m'
C_SEC=$'\e[38;5;81m'

# ---------------------------
# UI helpers
# ---------------------------
say()  { printf "%s\n" "$*"; }
warn() { printf "${C_WARN}WARNING:${R} %s\n" "$*" >&2; }
die()  { printf "${C_ERR}ERROR:${R} %s\n" "$*" >&2; exit 1; }

pause() {
  echo
  read -r -p "  Press Enter to continue..." _
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "This script must be run as root."
  fi
}

has_cmd() { command -v "$1" >/dev/null 2>&1; }

ensure_dirs() {
  mkdir -p "${BACKUP_DIR}"
}

backup_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  local ts
  ts="$(date +%Y%m%d-%H%M%S)"
  local dest="${BACKUP_DIR}/$(echo "$f" | sed 's#/#__#g').${ts}.bak"
  cp -a "$f" "$dest"
}

backup_dir_tar() {
  local d="$1"
  [[ -d "$d" ]] || return 0
  local ts
  ts="$(date +%Y%m%d-%H%M%S)"
  local dest="${BACKUP_DIR}/$(echo "$d" | sed 's#/#__#g').${ts}.tar.gz"
  tar -czf "$dest" -C "$(dirname "$d")" "$(basename "$d")"
}

confirm() {
  local prompt="${1:-Are you sure?} [y/N]: "
  read -r -p "$prompt" ans
  [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
}

# ---------------------------
# Logging
# ---------------------------
log_action() {
  local msg="$1"
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  printf "[%s] %s\n" "$ts" "$msg" >> "${LOG_FILE}"
}

show_log() {
  if [[ -f "${LOG_FILE}" ]]; then
    say "Last 20 entries from ${LOG_FILE}:"
    say ""
    tail -20 "${LOG_FILE}"
  else
    say "No log file found at ${LOG_FILE}."
  fi
}

# ---------------------------
# OS Check
# ---------------------------
check_os_supported() {
  if [[ ! -f /etc/os-release ]]; then
    warn "Cannot detect OS. Proceeding anyway."
    return 0
  fi
  local id id_like pretty
  id=$(. /etc/os-release && echo "${ID:-}")
  id_like=$(. /etc/os-release && echo "${ID_LIKE:-}")
  pretty=$(. /etc/os-release && echo "${PRETTY_NAME:-unknown}")

  if [[ "$id" == "ubuntu" || "$id" == "debian" \
     || "$id_like" == *"debian"* || "$id_like" == *"ubuntu"* ]]; then
    log_action "OS check passed: ${pretty}"
    return 0
  fi

  warn "Designed for Ubuntu/Debian. Detected: ${id} (${pretty})."
  if ! confirm "Continue anyway?"; then
    exit 1
  fi
}

# ---------------------------
# Internet Check
# ---------------------------
check_internet() {
  local host="${1:-8.8.8.8}"
  if ping -c1 -W3 "$host" >/dev/null 2>&1; then
    return 0
  fi
  warn "No internet connectivity detected (ping ${host} failed)."
  if ! confirm "Continue anyway?"; then
    return 1
  fi
  return 0
}

require_internet_or_warn() {
  check_internet || true
}

# ---------------------------
# Menu UI helpers
# ---------------------------
_sep() {
  printf "  ${C_DIM}$(printf -- '-%.0s' {1..52})${R}\n"
}

_menu_header() {
  local title="$1"
  echo
  printf "  ${BOLD}${C_TITLE}MrCerber Bootstrap${R}  ${C_DIM}|${R}  ${BOLD}%s${R}\n" "$title"
  _sep
  echo
}

_menu_item() {
  local num="$1" label="$2" desc="$3"
  printf "  ${C_NUM}%3s)${R}  ${BOLD}%-26s${R}  ${C_DIM}%s${R}\n" "$num" "$label" "$desc"
}

_menu_section() {
  printf "  ${C_SEC}%s${R}\n" "$1"
}

_status_badge() {
  local type="$1" name="$2"
  if [[ "$type" == "cmd" ]]; then
    has_cmd "$name" \
      && printf "${C_OK}installed${R}" \
      || printf "${C_DIM}not found${R}"
  elif [[ "$type" == "svc" ]]; then
    if systemctl is-active --quiet "$name" 2>/dev/null; then
      printf "${C_OK}active${R}"
    elif systemctl is-enabled --quiet "$name" 2>/dev/null; then
      printf "${C_WARN}stopped${R}"
    else
      printf "${C_DIM}inactive${R}"
    fi
  fi
}

# ---------------------------
# System / APT
# ---------------------------
apt_update_upgrade() {
  say "Updating package lists..."
  log_action "apt-get update"
  apt-get update -y
  say "Upgrading installed packages..."
  log_action "apt-get upgrade"
  DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
}

install_base_packages() {
  say "Installing base packages..."
  log_action "install_base_packages"
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates curl wget gnupg lsb-release \
    unzip zip tar \
    nano vim \
    htop btop \
    net-tools iproute2 \
    dnsutils \
    jq \
    git \
    ufw \
    fail2ban \
    unattended-upgrades \
    apt-listchanges \
    openssh-server
}

# ---------------------------
# Unattended Upgrades
# ---------------------------
enable_auto_updates() {
  say "Enabling unattended-upgrades..."
  log_action "enable_auto_updates"
  backup_file "/etc/apt/apt.conf.d/20auto-upgrades"
  backup_file "/etc/apt/apt.conf.d/50unattended-upgrades"

  cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

  cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'EOF'
Unattended-Upgrade::Allowed-Origins {
        "${distro_id}:${distro_codename}";
        "${distro_id}:${distro_codename}-security";
        "${distro_id}ESMApps:${distro_codename}-apps-security";
        "${distro_id}ESM:${distro_codename}-infra-security";
};

Unattended-Upgrade::Package-Blacklist {
};

Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-WithUsers "true";
Unattended-Upgrade::SyslogEnable "true";
EOF

  if has_cmd unattended-upgrade; then
    unattended-upgrade --dry-run --debug || true
  fi

  systemctl enable --now unattended-upgrades >/dev/null 2>&1 || true
  say "Unattended upgrades enabled."
}

# ---------------------------
# SSH tweaks (Last login)
# ---------------------------
sshd_set_printlastlog() {
  local value="$1"  # "yes" or "no"
  backup_file "${SSHD_CONFIG}"

  if grep -qiE '^\s*PrintLastLog\s+' "${SSHD_CONFIG}"; then
    sed -i -E "s/^\s*PrintLastLog\s+.*/PrintLastLog ${value}/I" "${SSHD_CONFIG}"
  else
    printf "\nPrintLastLog %s\n" "${value}" >> "${SSHD_CONFIG}"
  fi

  systemctl reload ssh >/dev/null 2>&1 || systemctl reload sshd >/dev/null 2>&1 || true
}

disable_last_login() {
  say "Disabling SSH 'Last login' message..."
  log_action "disable_last_login"
  sshd_set_printlastlog "no"
  say "Done."
}

restore_last_login() {
  say "Restoring SSH 'Last login' message..."
  log_action "restore_last_login"
  sshd_set_printlastlog "yes"
  say "Done."
}

ssh_change_port() {
  read -r -p "Enter new SSH port [1-65535]: " port
  if ! [[ "$port" =~ ^[0-9]{1,5}$ ]] || (( port < 1 || port > 65535 )); then
    warn "Invalid port."; return 0
  fi
  say "${C_WARN}Make sure UFW allows port ${port} before reconnecting!${R}"
  confirm "Change SSH port to ${port}?" || return 0
  backup_file "${SSHD_CONFIG}"
  if grep -qiE '^\s*Port\s+' "${SSHD_CONFIG}"; then
    sed -i -E "s/^\s*Port\s+.*/Port ${port}/" "${SSHD_CONFIG}"
  else
    printf "\nPort %s\n" "${port}" >> "${SSHD_CONFIG}"
  fi
  systemctl reload ssh >/dev/null 2>&1 || systemctl reload sshd >/dev/null 2>&1 || true
  log_action "ssh_change_port ${port}"
  say "SSH port changed to ${port}. Reconnect on the new port."
}

# ---------------------------
# MOTD management
# ---------------------------
disable_default_motd_scripts() {
  shopt -s nullglob
  for f in "${MOTD_DIR}/"*; do
    [[ -f "$f" ]] || continue
    local base
    base="$(basename "$f")"
    if [[ "$base" == "99-mrcerber" || "$base" == "logo.txt" ]]; then
      continue
    fi
    if [[ -x "$f" ]]; then
      chmod -x "$f" || true
    fi
  done
  shopt -u nullglob
}

enable_default_motd_scripts() {
  local defaults=(
    "00-header"
    "10-help-text"
    "50-motd-news"
    "50-landscape-sysinfo"
    "85-fwupd"
    "90-updates-available"
    "91-contract-ua-esm-status"
    "91-release-upgrade"
    "92-unattended-upgrades"
    "95-hwe-eol"
    "97-overlayroot"
    "98-fsck-at-reboot"
  )

  for base in "${defaults[@]}"; do
    if [[ -f "${MOTD_DIR}/${base}" ]]; then
      chmod +x "${MOTD_DIR}/${base}" || true
    fi
  done
}

install_custom_motd() {
  local motd_99_src="${CUSTOM_MOTD_99_SRC}"
  local motd_logo_src="${CUSTOM_MOTD_LOGO_SRC}"
  local tmp_dir=""

  if [[ ! -f "${motd_99_src}" || ! -f "${motd_logo_src}" ]]; then
    require_internet_or_warn
    if ! has_cmd curl && ! has_cmd wget; then
      die "Missing custom files and neither curl nor wget is available."
    fi
    say "Custom MOTD files not found next to this script; downloading..."
    tmp_dir="$(mktemp -d -t mrcerber-motd-XXXXXX)"
    if [[ ! -f "${motd_99_src}" ]]; then
      if has_cmd curl; then
        curl -fsSL "${MOTD_BASE_URL}/99-mrcerber" -o "${tmp_dir}/99-mrcerber"
      else
        wget -qO "${tmp_dir}/99-mrcerber" "${MOTD_BASE_URL}/99-mrcerber"
      fi
      motd_99_src="${tmp_dir}/99-mrcerber"
    fi
    if [[ ! -f "${motd_logo_src}" ]]; then
      if has_cmd curl; then
        curl -fsSL "${MOTD_BASE_URL}/logo.txt" -o "${tmp_dir}/logo.txt"
      else
        wget -qO "${tmp_dir}/logo.txt" "${MOTD_BASE_URL}/logo.txt"
      fi
      motd_logo_src="${tmp_dir}/logo.txt"
    fi
  fi

  [[ -f "${motd_99_src}" ]] || die "Missing custom file: ${motd_99_src}"
  [[ -f "${motd_logo_src}" ]] || die "Missing custom file: ${motd_logo_src}"

  say "Installing custom MOTD..."
  log_action "install_custom_motd"
  ensure_dirs
  backup_dir_tar "${MOTD_DIR}"

  install -m 0755 "${motd_99_src}" "${MOTD_DIR}/99-mrcerber"
  install -m 0644 "${motd_logo_src}" "${MOTD_DIR}/logo.txt"

  disable_default_motd_scripts
  disable_last_login

  say "Custom MOTD installed."

  if [[ -n "${tmp_dir}" ]]; then
    rm -rf "${tmp_dir}"
  fi
}

restore_default_motd() {
  say "Restoring default MOTD behavior..."
  log_action "restore_default_motd"
  ensure_dirs
  backup_dir_tar "${MOTD_DIR}"

  if [[ -f "${MOTD_DIR}/99-mrcerber" ]]; then rm -f "${MOTD_DIR}/99-mrcerber"; fi
  if [[ -f "${MOTD_DIR}/logo.txt" ]]; then rm -f "${MOTD_DIR}/logo.txt"; fi

  enable_default_motd_scripts
  restore_last_login

  say "Default MOTD restored (as far as system scripts exist on this server)."
}

preview_motd() {
  say "Previewing dynamic MOTD output:"
  say "----------------------------------------"
  run-parts "${MOTD_DIR}" || true
  say "----------------------------------------"
}

# ---------------------------
# Aliases
# ---------------------------
install_aliases() {
  say "Checking aliases in ${ALIASES_BASHRC}..."
  [[ -f "${ALIASES_BASHRC}" ]] || touch "${ALIASES_BASHRC}"
  backup_file "${ALIASES_BASHRC}"

  local added=0

  if grep -q "alias bench=" "${ALIASES_BASHRC}" 2>/dev/null; then
    say "  bench   : already exists, skipping."
  else
    printf "\nalias bench='wget -qO- bench.sh | bash'\n" >> "${ALIASES_BASHRC}"
    say "  ${C_OK}bench${R}   : added."
    log_action "alias bench added to ${ALIASES_BASHRC}"
    (( added++ )) || true
  fi

  if grep -q "alias geoip=" "${ALIASES_BASHRC}" 2>/dev/null; then
    say "  geoip   : already exists, skipping."
  else
    printf "alias geoip='bash <(wget -qO- https://github.com/vernette/ipregion/raw/master/ipregion.sh)'\n" >> "${ALIASES_BASHRC}"
    say "  ${C_OK}geoip${R}   : added."
    log_action "alias geoip added to ${ALIASES_BASHRC}"
    (( added++ )) || true
  fi

  if (( added > 0 )); then
    say ""
    say ""
    say "  ${C_WARN}NOTE:${R} Aliases require a manual reload to take effect:"
    say "  ${C_DIM}source ${ALIASES_BASHRC}${R}   <- apply in this session"
    say "  ${C_DIM}(or reconnect via SSH)${R}"
  fi
}

# ---------------------------
# Panels
# ---------------------------
install_1panel() {
  say "Installing 1Panel..."
  require_internet_or_warn
  log_action "install_1panel START"
  bash -c "$(curl -sSL https://resource.1panel.pro/v2/quick_start.sh)"
  log_action "install_1panel END"
}

install_3xui() {
  say "Installing 3x-ui..."
  require_internet_or_warn
  log_action "install_3xui START"
  bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
  log_action "install_3xui END"
}

cleanup_apt() {
  local before
  before="$(du -sh /var/cache/apt 2>/dev/null | awk '{print $1}')"
  say "Cache before cleanup: ${before}"
  say "Running autoremove + clean..."
  log_action "cleanup_apt"
  DEBIAN_FRONTEND=noninteractive apt-get autoremove -y
  apt-get clean
  local after
  after="$(du -sh /var/cache/apt 2>/dev/null | awk '{print $1}')"
  say "Cache after cleanup:  ${after}"
  say "Done."
}

# ---------------------------
# UFW menu
# ---------------------------
ufw_status() {
  ufw status verbose || true
}

ufw_basic_hardening() {
  say "Applying UFW defaults..."
  log_action "ufw_basic_hardening"
  ufw default deny incoming
  ufw default allow outgoing
  say "Done."
}

ufw_allow_ssh() {
  say "Allowing SSH (22/tcp)..."
  log_action "ufw allow 22/tcp"
  ufw allow 22/tcp
}

ufw_allow_http_https() {
  say "Allowing HTTP/HTTPS (80,443)..."
  log_action "ufw allow 80+443"
  ufw allow 80/tcp
  ufw allow 443/tcp
}

ufw_allow_custom() {
  read -r -p "Enter port (e.g., 8443): " port
  if ! [[ "$port" =~ ^[0-9]{1,5}$ ]] || (( port < 1 || port > 65535 )); then
    warn "Invalid port."; return 0
  fi
  read -r -p "Protocol (tcp/udp/both) [tcp]: " proto
  proto="${proto:-tcp}"
  case "${proto,,}" in
    tcp)  ufw allow "${port}/tcp"; log_action "ufw allow ${port}/tcp" ;;
    udp)  ufw allow "${port}/udp"; log_action "ufw allow ${port}/udp" ;;
    both) ufw allow "${port}/tcp"; ufw allow "${port}/udp"
          log_action "ufw allow ${port}/tcp+udp" ;;
    *)    warn "Invalid protocol."; return 0 ;;
  esac
}

ufw_delete_rule() {
  say "Current rules:"
  ufw status numbered || true
  read -r -p "Enter rule number to delete: " num
  [[ "$num" =~ ^[0-9]+$ ]] || { warn "Invalid number."; return 0; }
  ufw delete "$num"
  log_action "ufw delete rule ${num}"
}

ufw_enable() {
  say "Enabling UFW..."
  log_action "ufw enable"
  ufw --force enable
  systemctl enable --now ufw >/dev/null 2>&1 || true
}

ufw_disable() {
  say "Disabling UFW..."
  log_action "ufw disable"
  ufw disable
}

ufw_reset() {
  confirm "This will reset UFW (remove all rules). Continue?" || return 0
  log_action "ufw reset"
  ufw --force reset
}

ufw_menu() {
  while true; do
    clear
    _menu_header "UFW Firewall"
    _menu_item "1" "Status"            "show current rules (verbose)"
    _menu_item "2" "Apply defaults"    "deny incoming / allow outgoing"
    _menu_item "3" "Allow SSH"         "open 22/tcp"
    _menu_item "4" "Allow HTTP+HTTPS"  "open 80 + 443"
    _menu_item "5" "Allow custom port" "specify port + protocol"
    _menu_item "6" "Delete rule"       "remove rule by number"
    _menu_item "7" "Enable UFW"        "activate firewall"
    _menu_item "8" "Disable UFW"       "deactivate firewall"
    _menu_item "9" "Reset UFW"         "!! removes all rules !!"
    _menu_item "0" "Back"              ""
    read -r -p "  Select: " c
    case "$c" in
      1) ufw_status; pause ;;
      2) ufw_basic_hardening; pause ;;
      3) ufw_allow_ssh; pause ;;
      4) ufw_allow_http_https; pause ;;
      5) ufw_allow_custom; pause ;;
      6) ufw_delete_rule; pause ;;
      7) ufw_enable; pause ;;
      8) ufw_disable; pause ;;
      9) ufw_reset; pause ;;
      0) break ;;
      *) warn "Invalid choice."; pause ;;
    esac
  done
}

# ---------------------------
# Fail2ban menu
# ---------------------------
fail2ban_install_enable() {
  say "Installing/ensuring Fail2ban..."
  log_action "fail2ban_install_enable"
  DEBIAN_FRONTEND=noninteractive apt-get install -y fail2ban
  systemctl enable --now fail2ban
  say "Fail2ban enabled."
}

fail2ban_write_jail_local() {
  say "Writing /etc/fail2ban/jail.local (SSH protection)..."
  if [[ ! -d /etc/fail2ban ]]; then
    warn "Fail2ban not installed. Use 'Install + enable Fail2ban' first."
    return 0
  fi
  backup_file "/etc/fail2ban/jail.local"
  log_action "fail2ban_write_jail_local"

  cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5

backend = systemd
banaction = ufw

[sshd]
enabled  = true
mode     = normal
port     = ssh
logpath  = %(sshd_log)s
EOF

  if ! systemctl restart fail2ban >/dev/null 2>&1; then
    warn "Fail2ban restart failed. Ensure it is installed and enabled."
  fi
  say "jail.local written."
}

fail2ban_status() {
  systemctl status fail2ban --no-pager || true
  say ""
  fail2ban-client status || true
  say ""
  fail2ban-client status sshd || true
}

fail2ban_unban_ip() {
  read -r -p "Enter IP to unban: " ip
  [[ -n "$ip" ]] || { warn "IP cannot be empty."; return 0; }
  log_action "fail2ban unban ${ip}"
  fail2ban-client set sshd unbanip "$ip" || true
}

fail2ban_menu() {
  while true; do
    clear
    _menu_header "Fail2ban"
    _menu_item "1" "Install + enable"    "install fail2ban & start service"
    _menu_item "2" "Configure SSH jail"  "write /etc/fail2ban/jail.local"
    _menu_item "3" "Status"              "service status + sshd jail"
    _menu_item "4" "Unban IP"            "unban from sshd jail"
    _menu_item "0" "Back"                ""
    read -r -p "  Select: " c
    case "$c" in
      1) fail2ban_install_enable; pause ;;
      2) fail2ban_write_jail_local; pause ;;
      3) fail2ban_status; pause ;;
      4) fail2ban_unban_ip; pause ;;
      0) break ;;
      *) warn "Invalid choice."; pause ;;
    esac
  done
}

# ---------------------------
# Main menu actions
# ---------------------------
full_base_setup() {
  local start_ts
  start_ts="$(date +%s)"
  log_action "full_base_setup START"

  apt_update_upgrade
  install_base_packages
  enable_auto_updates

  local end_ts elapsed
  end_ts="$(date +%s)"
  elapsed=$(( end_ts - start_ts ))
  log_action "full_base_setup END (${elapsed}s)"

  echo
  printf "  ${BOLD}${C_OK}Setup Complete${R}\n"
  _sep
  printf "  %-22s ${C_OK}done${R}\n" "Packages updated:"
  printf "  %-22s ${C_OK}done${R}\n" "Base packages:"
  printf "  %-22s ${C_OK}done${R}\n" "Auto-updates:"
  printf "  %-22s %s\n"              "Duration:"    "${elapsed}s"
  printf "  %-22s ${C_DIM}%s${R}\n"  "Log:"         "${LOG_FILE}"
  echo
}

# ---------------------------
# Main menu
# ---------------------------
main_menu() {
  while true; do
    clear

    local ufw_s f2b_s
    ufw_s="$(_status_badge svc ufw)"
    f2b_s="$(_status_badge svc fail2ban)"

    echo
    printf "  ${BOLD}${C_TITLE}MrCerber — New Server Bootstrap${R}\n"
    printf "  ${C_DIM}Ubuntu / Debian  |  Run as root  |  Backups: %s${R}\n" "${BACKUP_DIR}"
    printf "  UFW: %s    Fail2ban: %s\n" "$ufw_s" "$f2b_s"
    _sep
    echo

    _menu_section "System"
    _menu_item " 1" "Full base setup"         "update + packages + auto-updates"
    _menu_item " 2" "Update / upgrade only"   "apt-get update && upgrade"
    _menu_item " 3" "Install base packages"   "curl, git, htop, btop, jq, ufw..."
    _menu_item " 4" "Enable auto-updates"     "unattended-upgrades"
    echo

    _menu_section "MOTD & SSH"
    _menu_item " 5" "Install custom MOTD"     "disable default + install 99-mrcerber"
    _menu_item " 6" "Restore default MOTD"    "re-enable system MOTD scripts"
    _menu_item " 7" "Preview MOTD"            "run-parts /etc/update-motd.d"
    _menu_item " 8" "Change SSH port"         "update Port in sshd_config"
    echo

    _menu_section "Security"
    _menu_item " 9" "UFW submenu"             "firewall rules & management"
    _menu_item "10" "Fail2ban submenu"        "SSH brute-force protection"
    echo

    _menu_section "Panels"
    _menu_item "11" "Install 1Panel"          "web-based server management panel"
    _menu_item "12" "Install 3x-ui"           "Xray-based proxy management panel"
    echo

    _menu_section "Extras"
    _menu_item "13" "Install aliases"         "bench, geoip  ->  /root/.bashrc"
    _menu_item "14" "APT cleanup"             "autoremove + clean apt cache"
    _menu_item "15" "Show action log"         "last 20 entries from bootstrap log"
    echo

    _sep
    _menu_item " 0" "Exit"                    ""
    echo

    read -r -p "  Select: " choice
    case "$choice" in
       1) full_base_setup; pause ;;
       2) apt_update_upgrade; pause ;;
       3) install_base_packages; pause ;;
       4) enable_auto_updates; pause ;;
       5) install_custom_motd; pause ;;
       6) restore_default_motd; pause ;;
       7) preview_motd; pause ;;
       8) ssh_change_port; pause ;;
       9) ufw_menu ;;
      10) fail2ban_menu ;;
      11) install_1panel; pause ;;
      12) install_3xui; pause ;;
      13) install_aliases; pause ;;
      14) cleanup_apt; pause ;;
      15) show_log; pause ;;
       0) exit 0 ;;
       *) warn "Invalid choice."; pause ;;
    esac
  done
}

# ---------------------------
# Entrypoint
# ---------------------------
require_root
ensure_dirs
check_os_supported
main_menu
