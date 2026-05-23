#!/usr/bin/env bash
# MrCerber - New Server Bootstrap (Ubuntu/Debian)
# Requirements:
# - MUST be run as root
# - SSH keys already installed for root (assumed)
#
# Features:
# - Interactive main menu + sub menus (UFW / Fail2ban / SSH)
# - Base packages install, sudo user creation, swap setup
# - Automatic security updates (unattended-upgrades)
# - Kernel/network security hardening (sysctl)
# - Disable default MOTD + disable SSH "Last login"
# - Install custom MOTD from two files: 99-mrcerber and logo.txt
# - Restore default MOTD + restore "Last login"
# - Install useful shell aliases (bench, geoip)
# - OS version check, internet connectivity check, action logging
# - Auto-reboot cron (Cron/Restart.sh integration)
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
# Cleanup trap
# ---------------------------
_TMPDIR=""
_cleanup() {
  local rc=$?
  [[ -n "$_TMPDIR" ]] && rm -rf "$_TMPDIR"
  (( rc != 0 )) && printf "\n%bScript exited with error (code %d). Check %s%b\n" \
    "$C_ERR" "$rc" "${LOG_FILE:-/root/.mrcerber-bootstrap.log}" "$R" >&2 || true
}
trap _cleanup EXIT

# ---------------------------
# Globals
# ---------------------------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"
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
  exec 9>/var/run/mrcerber-bootstrap.lock
  flock -n 9 || die "Another instance of this script is already running."
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
# User management
# ---------------------------
create_sudo_user() {
  local username
  while true; do
    read -r -p "Enter new username: " username
    [[ -n "$username" ]] || { warn "Username cannot be empty."; continue; }
    if ! [[ "$username" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
      warn "Invalid username. Use lowercase letters, digits, underscores, hyphens (max 32 chars)."; continue
    fi
    if id "$username" >/dev/null 2>&1; then
      warn "User '${username}' already exists."; return 0
    fi
    break
  done
  confirm "Create user '${username}' and add to sudo?" || return 0
  adduser --gecos "" "$username"
  usermod -aG sudo "$username"
  log_action "create_sudo_user ${username}"
  say "User '${username}' created and added to sudo group."
  read -r -p "  Paste SSH public key for ${username} (leave blank to skip): " pubkey
  if [[ -n "$pubkey" ]]; then
    local ssh_dir="/home/${username}/.ssh"
    mkdir -p "$ssh_dir"
    printf "%s\n" "$pubkey" >> "${ssh_dir}/authorized_keys"
    chmod 700 "$ssh_dir"
    chmod 600 "${ssh_dir}/authorized_keys"
    chown -R "${username}:${username}" "$ssh_dir"
    log_action "ssh key added for ${username}"
    say "SSH public key installed for '${username}'."
  fi
}

# ---------------------------
# Swap
# ---------------------------
setup_swap() {
  if swapon --show | grep -q .; then
    say "Swap is already configured:"
    swapon --show
    say ""
    confirm "Replace existing swap?" || return 0
    swapoff -a
    sed -i '/\bswap\b/d' /etc/fstab
    [[ -f /swapfile ]] && rm -f /swapfile
  fi
  local size
  while true; do
    read -r -p "Swap size (e.g. 1G, 2G, 512M): " size
    [[ -n "$size" ]] || { warn "Cannot be empty."; continue; }
    if ! [[ "$size" =~ ^[0-9]+[GgMm]$ ]]; then
      warn "Invalid format. Examples: 1G, 2G, 512M"; continue
    fi
    break
  done
  confirm "Create ${size} swapfile at /swapfile?" || return 0
  log_action "setup_swap ${size}"
  if ! fallocate -l "$size" /swapfile 2>/dev/null; then
    warn "fallocate failed (btrfs?); falling back to dd..."
    local mb
    case "${size^^}" in
      *G) mb=$(( ${size%[Gg]} * 1024 )) ;;
      *M) mb=${size%[Mm]} ;;
      *)  die "Cannot parse size." ;;
    esac
    dd if=/dev/zero of=/swapfile bs=1M count="$mb" status=progress
  fi
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '/swapfile' /etc/fstab || printf "\n/swapfile none swap sw 0 0\n" >> /etc/fstab
  printf "vm.swappiness=10\nvm.vfs_cache_pressure=50\n" \
    > /etc/sysctl.d/99-mrcerber-swap.conf
  sysctl --system >/dev/null 2>&1 || true
  say "Swap configured: ${size} at /swapfile (swappiness=10)"
  swapon --show
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
_sshd_validate_and_reload() {
  if ! sshd -t -f "${SSHD_CONFIG}" 2>/dev/null; then
    warn "sshd config validation failed — restoring backup"
    local latest_bak
    latest_bak="$(ls -t "${BACKUP_DIR}"/*sshd_config* 2>/dev/null | head -1 || true)"
    [[ -n "$latest_bak" ]] && cp "$latest_bak" "${SSHD_CONFIG}"
    die "SSH config is invalid. Backup restored. No reload performed."
  fi
  systemctl reload ssh >/dev/null 2>&1 || systemctl reload sshd >/dev/null 2>&1 \
    || warn "SSH reload failed — run: systemctl restart ssh"
}

sshd_set_printlastlog() {
  local value="$1"  # "yes" or "no"
  backup_file "${SSHD_CONFIG}"

  if grep -qiE '^\s*PrintLastLog\s+' "${SSHD_CONFIG}"; then
    sed -i -E "s/^\s*PrintLastLog\s+.*/PrintLastLog ${value}/I" "${SSHD_CONFIG}"
  else
    printf "\nPrintLastLog %s\n" "${value}" >> "${SSHD_CONFIG}"
  fi

  _sshd_validate_and_reload
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
  confirm "Change SSH port to ${port}?" || return 0
  backup_file "${SSHD_CONFIG}"
  if grep -qiE '^\s*Port\s+' "${SSHD_CONFIG}"; then
    sed -i -E "s/^\s*Port\s+.*/Port ${port}/" "${SSHD_CONFIG}"
  else
    printf "\nPort %s\n" "${port}" >> "${SSHD_CONFIG}"
  fi
  _sshd_validate_and_reload
  if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "^Status: active"; then
    ufw allow "${port}/tcp" comment "SSH" >/dev/null
    say "UFW rule for port ${port}/tcp added automatically."
  fi
  log_action "ssh_change_port ${port}"
  say "SSH port changed to ${port}. Reconnect on the new port."
}

ssh_status() {
  say "Current SSH security settings (${SSHD_CONFIG}):"
  say ""
  local port auth root_login printlastlog
  port="$(grep -iE '^\s*Port\s+' "${SSHD_CONFIG}" 2>/dev/null | awk '{print $2}' | tail -1 || true)"
  auth="$(grep -iE '^\s*PasswordAuthentication\s+' "${SSHD_CONFIG}" 2>/dev/null | awk '{print $2}' | tail -1 || true)"
  root_login="$(grep -iE '^\s*PermitRootLogin\s+' "${SSHD_CONFIG}" 2>/dev/null | awk '{print $2}' | tail -1 || true)"
  printlastlog="$(grep -iE '^\s*PrintLastLog\s+' "${SSHD_CONFIG}" 2>/dev/null | awk '{print $2}' | tail -1 || true)"
  printf "  %-30s %s\n" "Port:"                   "${port:-22 (default)}"
  printf "  %-30s %s\n" "PasswordAuthentication:" "${auth:-yes (default)}"
  printf "  %-30s %s\n" "PermitRootLogin:"        "${root_login:-yes (default)}"
  printf "  %-30s %s\n" "PrintLastLog:"           "${printlastlog:-yes (default)}"
}

ssh_disable_password_auth() {
  say "Disabling SSH password authentication (key-only login)..."
  warn "This will lock out password-based SSH logins. Ensure you have a working key."
  confirm "Continue?" || return 0
  backup_file "${SSHD_CONFIG}"
  if grep -qiE '^\s*PasswordAuthentication\s+' "${SSHD_CONFIG}"; then
    sed -i -E "s/^\s*PasswordAuthentication\s+.*/PasswordAuthentication no/I" "${SSHD_CONFIG}"
  else
    printf "\nPasswordAuthentication no\n" >> "${SSHD_CONFIG}"
  fi
  _sshd_validate_and_reload
  log_action "ssh_disable_password_auth"
  say "Password authentication disabled. Key-based login only."
}

ssh_restrict_root_login() {
  say "Setting PermitRootLogin to prohibit-password..."
  say "Root can still log in with SSH keys; password login for root will be blocked."
  confirm "Continue?" || return 0
  backup_file "${SSHD_CONFIG}"
  if grep -qiE '^\s*PermitRootLogin\s+' "${SSHD_CONFIG}"; then
    sed -i -E "s/^\s*PermitRootLogin\s+.*/PermitRootLogin prohibit-password/I" "${SSHD_CONFIG}"
  else
    printf "\nPermitRootLogin prohibit-password\n" >> "${SSHD_CONFIG}"
  fi
  _sshd_validate_and_reload
  log_action "ssh_restrict_root_login"
  say "Root password login disabled (key-based root login still works)."
}

ssh_menu() {
  while true; do
    clear
    _menu_header "SSH Hardening"
    _menu_item "1" "Status"                  "show key sshd_config settings"
    _menu_item "2" "Disable password auth"   "key-only login (PasswordAuthentication no)"
    _menu_item "3" "Restrict root login"     "prohibit-password (keys only for root)"
    _menu_item "4" "Change SSH port"         "update Port in sshd_config"
    _menu_item "0" "Back"                    ""
    read -r -p "  Select: " c
    case "$c" in
      1) ssh_status; pause ;;
      2) ssh_disable_password_auth; pause ;;
      3) ssh_restrict_root_login; pause ;;
      4) ssh_change_port; pause ;;
      0) break ;;
      *) warn "Invalid choice."; pause ;;
    esac
  done
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

  if [[ ! -f "${motd_99_src}" || ! -f "${motd_logo_src}" ]]; then
    require_internet_or_warn
    if ! has_cmd curl && ! has_cmd wget; then
      die "Missing custom files and neither curl nor wget is available."
    fi
    say "Custom MOTD files not found next to this script; downloading..."
    _TMPDIR="$(mktemp -d -t mrcerber-motd-XXXXXX)"
    if [[ ! -f "${motd_99_src}" ]]; then
      if has_cmd curl; then
        curl -fsSL --max-time 30 "${MOTD_BASE_URL}/99-mrcerber" -o "${_TMPDIR}/99-mrcerber"
      else
        wget -qO "${_TMPDIR}/99-mrcerber" "${MOTD_BASE_URL}/99-mrcerber"
      fi
      motd_99_src="${_TMPDIR}/99-mrcerber"
    fi
    if [[ ! -f "${motd_logo_src}" ]]; then
      if has_cmd curl; then
        curl -fsSL --max-time 30 "${MOTD_BASE_URL}/logo.txt" -o "${_TMPDIR}/logo.txt"
      else
        wget -qO "${_TMPDIR}/logo.txt" "${MOTD_BASE_URL}/logo.txt"
      fi
      motd_logo_src="${_TMPDIR}/logo.txt"
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
  _TMPDIR=""
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

create_script_alias() {
  say "Creating script launcher alias..."
  [[ -f "${ALIASES_BASHRC}" ]] || touch "${ALIASES_BASHRC}"
  backup_file "${ALIASES_BASHRC}"

  local alias_name="mrc-tools"
  local alias_cmd="bash <(curl -fsSL https://raw.githubusercontent.com/MrCerber/Server-Tools/refs/heads/main/install.sh)"

  if grep -q "alias ${alias_name}=" "${ALIASES_BASHRC}" 2>/dev/null; then
    say "  ${alias_name} : already exists, skipping."
  else
    printf "\nalias %s='%s'\n" "${alias_name}" "${alias_cmd}" >> "${ALIASES_BASHRC}"
    say "  ${C_OK}${alias_name}${R} : added  ->  ${C_DIM}${ALIASES_BASHRC}${R}"
    log_action "alias ${alias_name} added to ${ALIASES_BASHRC}"
    say ""
    say "  ${C_WARN}NOTE:${R} Reload to apply:"
    say "  ${C_DIM}source ${ALIASES_BASHRC}${R}   <- this session"
    say "  ${C_DIM}(or reconnect via SSH)${R}"
  fi
}

# ---------------------------
# Panels
# ---------------------------
install_docker() {
  if has_cmd docker; then
    say "Docker is already installed: $(docker --version)"
    confirm "Re-install anyway?" || return 0
  fi
  warn "This will download and execute the official Docker install script as root:"
  say "  https://get.docker.com"
  confirm "Continue?" || return 0
  say "Installing Docker..."
  require_internet_or_warn
  log_action "install_docker START"
  curl -fsSL https://get.docker.com | sh
  log_action "install_docker END"
  say "Docker installed: $(docker --version 2>/dev/null || echo 'unknown')"
}

install_1panel() {
  warn "This will download and execute an external installer script as root:"
  say "  https://resource.1panel.pro/v2/quick_start.sh"
  confirm "Continue?" || return 0
  say "Installing 1Panel..."
  require_internet_or_warn
  log_action "install_1panel START"
  bash -c "$(curl -sSL --max-time 60 https://resource.1panel.pro/v2/quick_start.sh)"
  log_action "install_1panel END"
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
# Auto-reboot cron
# ---------------------------
setup_auto_reboot_cron() {
  local src="${SCRIPT_DIR}/Cron/Restart.sh"
  local dest="/usr/local/sbin/mrcerber-auto-reboot.sh"
  local cron_file="/etc/cron.d/mrcerber-auto-reboot"

  if [[ -f "$cron_file" ]]; then
    say "Auto-reboot cron is currently active:"
    cat "$cron_file"
    say ""
    confirm "Reconfigure?" || {
      if confirm "Disable auto-reboot cron?"; then
        rm -f "$cron_file"
        log_action "setup_auto_reboot_cron DISABLED"
        say "Auto-reboot cron removed."
      fi
      return 0
    }
  fi

  if [[ ! -f "$src" ]]; then
    require_internet_or_warn
    say "Downloading Cron/Restart.sh from GitHub..."
    _TMPDIR="$(mktemp -d -t mrcerber-cron-XXXXXX)"
    if has_cmd curl; then
      curl -fsSL --max-time 30 "${MOTD_BASE_URL}/Cron/Restart.sh" -o "${_TMPDIR}/Restart.sh" \
        || { warn "Failed to download Restart.sh."; _TMPDIR=""; return 0; }
    else
      wget -qO "${_TMPDIR}/Restart.sh" "${MOTD_BASE_URL}/Cron/Restart.sh" \
        || { warn "Failed to download Restart.sh."; _TMPDIR=""; return 0; }
    fi
    src="${_TMPDIR}/Restart.sh"
  fi

  confirm "Install auto-reboot cron (runs hourly, reboots only if kernel update pending)?" || return 0
  install -m 0750 "$src" "$dest"
  printf "# MrCerber auto-reboot\n0 * * * * root %s >> /var/log/mrcerber-auto-reboot.log 2>&1\n" \
    "$dest" > "$cron_file"
  chmod 644 "$cron_file"
  _TMPDIR=""
  log_action "setup_auto_reboot_cron ENABLED"
  say "Auto-reboot cron installed."
  say "  Script : ${dest}"
  say "  Cron   : ${cron_file} (runs hourly)"
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

ufw_allow_from_ip() {
  local src_ip port proto
  while true; do
    read -r -p "Source IP or CIDR (e.g. 1.2.3.4 or 1.2.3.0/24): " src_ip
    [[ -n "$src_ip" ]] || { warn "Cannot be empty."; continue; }
    if [[ ! "$src_ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/([0-9]|[1-2][0-9]|3[0-2]))?$ ]]; then
      warn "Invalid IP or CIDR format."; continue
    fi
    break
  done
  while true; do
    read -r -p "Port to open (1-65535): " port
    if [[ ! "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
      warn "Invalid port number."; continue
    fi
    break
  done
  read -r -p "Protocol [tcp/udp/both] (default: tcp): " proto
  proto="${proto:-tcp}"
  case "${proto,,}" in
    tcp|udp)
      ufw allow from "$src_ip" to any port "$port" proto "${proto,,}"
      log_action "ufw allow from ${src_ip} to any port ${port} proto ${proto,,}"
      ;;
    both)
      ufw allow from "$src_ip" to any port "$port" proto tcp
      ufw allow from "$src_ip" to any port "$port" proto udp
      log_action "ufw allow from ${src_ip} to any port ${port} proto tcp+udp"
      ;;
    *)
      warn "Invalid protocol. Use tcp, udp, or both."; return 0 ;;
  esac
  say "Rule added: allow from ${src_ip} to port ${port}/${proto}"
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
    _menu_item "1"  "Status"              "show current rules (verbose)"
    _menu_item "2"  "Apply defaults"      "deny incoming / allow outgoing"
    _menu_item "3"  "Allow SSH"           "open 22/tcp"
    _menu_item "4"  "Allow HTTP+HTTPS"    "open 80 + 443"
    _menu_item "5"  "Allow custom port"   "specify port + protocol"
    _menu_item "6"  "Allow from IP/CIDR"  "open port for a specific source IP"
    _menu_item "7"  "Delete rule"         "remove rule by number"
    _menu_item "8"  "Enable UFW"          "activate firewall"
    _menu_item "9"  "Disable UFW"         "deactivate firewall"
    _menu_item "10" "Reset UFW"           "!! removes all rules !!"
    _menu_item "0"  "Back"                ""
    read -r -p "  Select: " c
    case "$c" in
       1) ufw_status; pause ;;
       2) ufw_basic_hardening; pause ;;
       3) ufw_allow_ssh; pause ;;
       4) ufw_allow_http_https; pause ;;
       5) ufw_allow_custom; pause ;;
       6) ufw_allow_from_ip; pause ;;
       7) ufw_delete_rule; pause ;;
       8) ufw_enable; pause ;;
       9) ufw_disable; pause ;;
      10) ufw_reset; pause ;;
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
  say "Writing /etc/fail2ban/jail.local (VPS SSH protection)..."
  if [[ ! -d /etc/fail2ban ]]; then
    warn "Fail2ban not installed. Use 'Install + enable Fail2ban' first."
    return 0
  fi
  backup_file "/etc/fail2ban/jail.local"
  log_action "fail2ban_write_jail_local"

  cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
# Progressive banning: each repeat offence multiplies the ban duration (24x per offence)
bantime.increment  = true
bantime.multiplier = 24
bantime.maxtime    = 720h
bantime            = 1h
findtime           = 10m
maxretry           = 3
backend            = systemd
banaction          = ufw
ignoreip           = 127.0.0.1/8 ::1

[sshd]
enabled = true
# aggressive mode catches pre-authentication floods in addition to auth failures
mode    = aggressive
port    = ssh
logpath = %(syslog_authpriv)s

[recidive]
# IPs that get banned multiple times receive a 30-day block
enabled   = true
logpath   = /var/log/fail2ban.log
banaction = ufw
bantime   = 720h
findtime  = 1d
maxretry  = 5
EOF

  if ! systemctl restart fail2ban >/dev/null 2>&1; then
    warn "Fail2ban restart failed. Ensure it is installed and enabled."
  else
    say "Fail2ban restarted with new config."
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
  if [[ ! "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    warn "Invalid IP address format."; return 0
  fi
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
# Kernel hardening
# ---------------------------
apply_sysctl_hardening() {
  local conf="/etc/sysctl.d/99-mrcerber-hardening.conf"
  if [[ -f "$conf" ]]; then
    say "Kernel hardening already applied (${conf} exists)."
    confirm "Re-apply / overwrite?" || return 0
  fi
  log_action "apply_sysctl_hardening"
  cat > "$conf" <<'EOF'
# MrCerber — kernel network security hardening
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv6.conf.all.forwarding = 0
EOF
  sysctl --system >/dev/null 2>&1 || true
  say "Kernel hardening applied. Settings written to ${conf}."
}

# ---------------------------
# Scripts submenu
# ---------------------------
run_script() {
  local name="$1"
  local path="${SCRIPTS_DIR}/${name}"
  if [[ ! -f "$path" ]]; then
    require_internet_or_warn
    if ! has_cmd curl && ! has_cmd wget; then
      warn "Script not found locally and neither curl nor wget is available."
      return 0
    fi
    say "Script not found locally; downloading from GitHub..."
    _TMPDIR="$(mktemp -d -t mrcerber-scripts-XXXXXX)"
    if has_cmd curl; then
      if ! curl -fsSL --max-time 30 "${MOTD_BASE_URL}/scripts/${name}" \
           -o "${_TMPDIR}/${name}"; then
        warn "Failed to download ${name}."; _TMPDIR=""; return 0
      fi
    else
      if ! wget -qO "${_TMPDIR}/${name}" "${MOTD_BASE_URL}/scripts/${name}"; then
        warn "Failed to download ${name}."; _TMPDIR=""; return 0
      fi
    fi
    path="${_TMPDIR}/${name}"
  fi
  bash "$path"
  _TMPDIR=""
}

scripts_menu() {
  while true; do
    clear
    _menu_header "Scripts"
    _menu_item "1" "Cloudflare DNS Manager"  "manage DNS A-records via Cloudflare API"
    _menu_item "2" "Enable BBR"              "TCP BBR congestion control + fq scheduler"
    _menu_item "0" "Back"                    ""
    read -r -p "  Select: " c
    case "$c" in
      1) run_script "cf_dns_manager.sh" ;;
      2) run_script "enable_bbr.sh"; pause ;;
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

    _menu_section "Quick Setup"
    _menu_item " 1" "Create launcher alias"   "alias mrc-tools -> run this script from anywhere"
    echo

    _menu_section "System"
    _menu_item " 2" "Full base setup"         "update + packages + auto-updates"
    _menu_item " 3" "Update / upgrade only"   "apt-get update && upgrade"
    _menu_item " 4" "Install base packages"   "curl, git, htop, btop, jq, ufw..."
    _menu_item " 5" "Enable auto-updates"     "unattended-upgrades"
    _menu_item " 6" "Create sudo user"        "add non-root user with sudo + SSH key"
    _menu_item " 7" "Setup swap"              "create /swapfile + persist in fstab"
    echo

    _menu_section "MOTD & SSH"
    _menu_item " 8" "Install custom MOTD"     "disable default + install 99-mrcerber"
    _menu_item " 9" "Restore default MOTD"    "re-enable system MOTD scripts"
    _menu_item "10" "Preview MOTD"            "run-parts /etc/update-motd.d"
    _menu_item "11" "SSH submenu"             "port, password auth, root login hardening"
    echo

    _menu_section "Security"
    _menu_item "12" "UFW submenu"             "firewall rules & management"
    _menu_item "13" "Fail2ban submenu"        "SSH brute-force protection"
    _menu_item "14" "Kernel hardening"        "sysctl: SYN cookies, anti-spoof, redirects"
    echo

    _menu_section "Panels"
    _menu_item "15" "Install Docker"          "official get.docker.com installer"
    _menu_item "16" "Install 1Panel"          "web-based server management panel"
    echo

    _menu_section "Extras"
    _menu_item "17" "Install aliases"         "bench, geoip  ->  /root/.bashrc"
    _menu_item "18" "APT cleanup"             "autoremove + clean apt cache"
    _menu_item "19" "Auto-reboot cron"        "install/manage Cron/Restart.sh"
    _menu_item "20" "Show action log"         "last 20 entries from bootstrap log"
    echo

    _menu_section "Scripts"
    _menu_item "21" "Scripts submenu"         "run utility scripts (DNS, BBR...)"
    echo

    _sep
    _menu_item " 0" "Exit"                    ""
    echo

    read -r -p "  Select: " choice
    case "$choice" in
       1) create_script_alias; pause ;;
       2) full_base_setup; pause ;;
       3) apt_update_upgrade; pause ;;
       4) install_base_packages; pause ;;
       5) enable_auto_updates; pause ;;
       6) create_sudo_user; pause ;;
       7) setup_swap; pause ;;
       8) install_custom_motd; pause ;;
       9) restore_default_motd; pause ;;
      10) preview_motd; pause ;;
      11) ssh_menu ;;
      12) ufw_menu ;;
      13) fail2ban_menu ;;
      14) apply_sysctl_hardening; pause ;;
      15) install_docker; pause ;;
      16) install_1panel; pause ;;
      17) install_aliases; pause ;;
      18) cleanup_apt; pause ;;
      19) setup_auto_reboot_cron; pause ;;
      20) show_log; pause ;;
      21) scripts_menu ;;
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
