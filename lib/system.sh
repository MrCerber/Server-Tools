#!/usr/bin/env bash
# System management functions — sourced by install-tui.sh

# ── APT ───────────────────────────────────────────────────────────────────────
apt_update_upgrade() {
  log_action "apt_update_upgrade"
  gum_spin "${T[sys_updating]}" apt-get update -y
  DEBIAN_FRONTEND=noninteractive gum_spin "${T[sys_upgrading]}" \
    apt-get upgrade -y
}

install_base_packages() {
  log_action "install_base_packages"
  DEBIAN_FRONTEND=noninteractive gum_spin "${T[sys_installing_base]}" \
    apt-get install -y \
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

cleanup_apt() {
  local before after
  before="$(du -sh /var/cache/apt 2>/dev/null | awk '{print $1}')"
  say "$(_t apt_before "$before")"
  log_action "cleanup_apt"
  DEBIAN_FRONTEND=noninteractive gum_spin "autoremove..." apt-get autoremove -y
  apt-get clean
  after="$(du -sh /var/cache/apt 2>/dev/null | awk '{print $1}')"
  say "$(_t apt_after "$after")"
}

# ── Auto-updates ──────────────────────────────────────────────────────────────
enable_auto_updates() {
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
    unattended-upgrade --dry-run --debug >/dev/null 2>&1 || true
  fi
  systemctl enable --now unattended-upgrades >/dev/null 2>&1 || true
  say "${T[sys_auto_updates_done]}"
}

# ── User management ───────────────────────────────────────────────────────────
create_sudo_user() {
  local username
  while true; do
    username=$(gum_input "${T[user_prompt]}") || return 0
    [[ -n "$username" ]] || { warn "${T[cannot_be_empty]}"; continue; }
    if ! [[ "$username" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
      warn "${T[user_invalid]}"; continue
    fi
    if id "$username" >/dev/null 2>&1; then
      warn "$(_t user_exists "$username")"; return 0
    fi
    break
  done

  gum_confirm "$(_t user_confirm "$username")" || return 0
  adduser --gecos "" "$username"
  usermod -aG sudo "$username"
  log_action "create_sudo_user ${username}"
  say "$(_t user_done "$username")"

  local pubkey
  pubkey=$(gum_input "$(_t user_ssh_key_prompt "$username")") || true
  if [[ -n "$pubkey" ]]; then
    if ! _validate_ssh_pubkey "$pubkey"; then
      warn "${T[user_ssh_key_invalid]}"; return 0
    fi
    local ssh_dir="/home/${username}/.ssh"
    mkdir -p "$ssh_dir"
    printf "%s\n" "$pubkey" >> "${ssh_dir}/authorized_keys"
    chmod 700 "$ssh_dir"
    chmod 600 "${ssh_dir}/authorized_keys"
    chown -R "${username}:${username}" "$ssh_dir"
    log_action "ssh key added for ${username}"
    say "$(_t user_ssh_key_done "$username")"
  fi
}

# ── Swap ──────────────────────────────────────────────────────────────────────
setup_swap() {
  if grep -q '\bswap\b' /proc/swaps 2>/dev/null && [[ "$(wc -l < /proc/swaps)" -gt 1 ]]; then
    say "${T[swap_exists]}"
    cat /proc/swaps
    echo
    gum_confirm "${T[swap_replace_confirm]}" || return 0
    swapoff -a
    sed -i '/\bswap\b/d' /etc/fstab
    [[ -f /swapfile ]] && rm -f /swapfile
  fi

  local size
  while true; do
    size=$(gum_input "${T[swap_size_prompt]}") || return 0
    [[ -n "$size" ]] || { warn "${T[cannot_be_empty]}"; continue; }
    if ! [[ "$size" =~ ^[0-9]+[GgMm]$ ]]; then
      warn "${T[err_invalid_size]}"; continue
    fi
    local num="${size%[GgMmGGMM]}"
    (( num > 0 )) || { warn "${T[err_invalid_size]}"; continue; }
    break
  done

  gum_confirm "$(_t swap_create_confirm "$size")" || return 0
  log_action "setup_swap ${size}"

  if ! fallocate -l "$size" /swapfile 2>/dev/null; then
    warn "${T[swap_fallocate_fail]}"
    local mb
    case "${size^^}" in
      *G) mb=$(( ${size%[Gg]} * 1024 )) ;;
      *M) mb=${size%[Mm]} ;;
      *)  die "${T[err_invalid_size]}" ;;
    esac
    gum_spin "Creating swapfile via dd..." dd if=/dev/zero of=/swapfile bs=1M count="$mb"
  fi

  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '/swapfile' /etc/fstab \
    || printf "\n/swapfile none swap sw 0 0\n" >> /etc/fstab
  printf "vm.swappiness=10\nvm.vfs_cache_pressure=50\n" \
    > /etc/sysctl.d/99-mrcerber-swap.conf
  sysctl --system >/dev/null 2>&1 || true
  say "$(_t swap_done "$size")"
  cat /proc/swaps
}

# ── Kernel hardening ──────────────────────────────────────────────────────────
apply_sysctl_hardening() {
  local conf="/etc/sysctl.d/99-mrcerber-hardening.conf"
  if [[ -f "$conf" ]]; then
    say "${T[hardening_exists]}"
    gum_confirm "${T[hardening_reapply]}" || return 0
  fi
  log_action "apply_sysctl_hardening"
  cat > "$conf" <<'EOF'
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
  say "${T[hardening_done]}"
}

# ── Shell aliases ─────────────────────────────────────────────────────────────
install_aliases() {
  [[ -f "${ALIASES_BASHRC}" ]] || touch "${ALIASES_BASHRC}"
  backup_file "${ALIASES_BASHRC}"

  local -A aliases=(
    [bench]="wget -qO- bench.sh | bash"
    [geoip]="bash <(wget -qO- https://github.com/vernette/ipregion/raw/master/ipregion.sh)"
  )
  local added=0

  local name cmd
  for name in "${!aliases[@]}"; do
    cmd="${aliases[$name]}"
    if grep -q "alias ${name}=" "${ALIASES_BASHRC}" 2>/dev/null; then
      say "  ${name}: ${T[alias_exists]}"
    else
      printf "\nalias %s='%s'\n" "${name}" "${cmd}" >> "${ALIASES_BASHRC}"
      say "  ${name}: ${T[alias_added]}"
      log_action "alias ${name} added to ${ALIASES_BASHRC}"
      (( added++ )) || true
    fi
  done

  if (( added > 0 )); then
    echo
    say "${T[alias_reload_note]}"
  fi
}

create_script_alias() {
  [[ -f "${ALIASES_BASHRC}" ]] || touch "${ALIASES_BASHRC}"
  backup_file "${ALIASES_BASHRC}"

  local alias_name="mrc-tools"
  local alias_cmd="bash <(curl -fsSL https://raw.githubusercontent.com/MrCerber/Server-Tools/refs/heads/main/install.sh)"

  if grep -q "alias ${alias_name}=" "${ALIASES_BASHRC}" 2>/dev/null; then
    say "  ${alias_name}: ${T[alias_exists]}"
  else
    printf "\nalias %s='%s'\n" "${alias_name}" "${alias_cmd}" >> "${ALIASES_BASHRC}"
    say "  ${alias_name}: ${T[alias_added]}"
    log_action "alias ${alias_name} added to ${ALIASES_BASHRC}"
    echo
    say "${T[alias_reload_note]}"
  fi
}

# ── Auto-reboot cron ──────────────────────────────────────────────────────────
setup_auto_reboot_cron() {
  local src="${SCRIPT_DIR}/Cron/Restart.sh"
  local dest="/usr/local/sbin/mrcerber-auto-reboot.sh"
  local cron_file="/etc/cron.d/mrcerber-auto-reboot"

  if [[ -f "$cron_file" ]]; then
    say "${T[cron_active]}"
    cat "$cron_file"
    echo
    if ! gum_confirm "${T[cron_reconfigure]}"; then
      if gum_confirm "${T[cron_disable_confirm]}"; then
        rm -f "$cron_file"
        log_action "setup_auto_reboot_cron DISABLED"
        say "${T[cron_disabled]}"
      fi
      return 0
    fi
  fi

  if [[ ! -f "$src" ]]; then
    require_internet_or_warn
    say "${T[scripts_downloading]}"
    _TMPDIR="$(mktemp -d -t mrcerber-cron-XXXXXX)"
    if ! _download_file "${MOTD_BASE_URL}/Cron/Restart.sh" "${_TMPDIR}/Restart.sh"; then
      warn "Failed to download Restart.sh."
      _TMPDIR=""; return 0
    fi
    src="${_TMPDIR}/Restart.sh"
  fi

  gum_confirm "${T[cron_install_confirm]}" || return 0
  install -m 0750 "$src" "$dest"
  printf "# MrCerber auto-reboot\n0 * * * * root %s >> /var/log/mrcerber-auto-reboot.log 2>&1\n" \
    "$dest" > "$cron_file"
  chmod 644 "$cron_file"
  _TMPDIR=""
  log_action "setup_auto_reboot_cron ENABLED"
  say "${T[cron_done]}"
}

# ── Full setup composite ──────────────────────────────────────────────────────
full_base_setup() {
  local start_ts; start_ts="$(date +%s)"
  log_action "full_base_setup START"

  apt_update_upgrade
  install_base_packages
  enable_auto_updates

  local elapsed=$(( $(date +%s) - start_ts ))
  log_action "full_base_setup END (${elapsed}s)"
  echo
  gum style --foreground 82 --bold "  ${T[full_setup_done]}"
  printf "  %-24s OK\n" "${T[full_setup_packages]}"
  printf "  %-24s OK\n" "${T[full_setup_base]}"
  printf "  %-24s OK\n" "${T[full_setup_updates]}"
  printf "  %-24s %ss\n" "${T[full_setup_duration]}" "${elapsed}"
  echo
}
