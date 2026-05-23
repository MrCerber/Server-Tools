#!/usr/bin/env bash
# Fail2ban functions — sourced by install-tui.sh

fail2ban_install_enable() {
  log_action "fail2ban_install_enable"
  DEBIAN_FRONTEND=noninteractive gum_spin "Installing fail2ban..." \
    apt-get install -y fail2ban
  systemctl enable --now fail2ban
  say "${T[f2b_done]}"
}

fail2ban_write_jail_local() {
  if [[ ! -d /etc/fail2ban ]]; then
    warn "${T[f2b_not_installed]}"; return 0
  fi
  backup_file "/etc/fail2ban/jail.local"
  log_action "fail2ban_write_jail_local"

  cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
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
mode    = aggressive
port    = ssh
logpath = %(syslog_authpriv)s

[recidive]
enabled   = true
logpath   = /var/log/fail2ban.log
banaction = ufw
bantime   = 720h
findtime  = 1d
maxretry  = 5
EOF

  if ! systemctl restart fail2ban >/dev/null 2>&1; then
    warn "${T[f2b_restart_failed]}"
  else
    say "${T[f2b_jail_done]}"
  fi
}

fail2ban_status() {
  systemctl status fail2ban --no-pager 2>/dev/null || true
  echo
  if has_cmd fail2ban-client; then
    fail2ban-client status 2>/dev/null || true
    echo
    fail2ban-client status sshd 2>/dev/null || true
  fi
}

fail2ban_unban_ip() {
  local ip
  ip=$(gum_input "${T[f2b_unban_prompt]}") || return 0
  [[ -n "$ip" ]] || { warn "${T[cannot_be_empty]}"; return 0; }
  _validate_ipv4 "$ip" || { warn "${T[err_invalid_ip]}"; return 0; }
  log_action "fail2ban unban ${ip}"
  fail2ban-client set sshd unbanip "$ip" 2>/dev/null || true
}

fail2ban_menu() {
  while true; do
    clear
    gum_header "${T[f2b_menu_title]}"

    local choice
    choice=$(gum choose --cursor="▶ " \
      "${T[f2b_m_install]}" \
      "${T[f2b_m_jail]}" \
      "${T[f2b_m_status]}" \
      "${T[f2b_m_unban]}" \
      "${T[back]}") || break

    case "$choice" in
      "${T[f2b_m_install]}") fail2ban_install_enable; gum_pause ;;
      "${T[f2b_m_jail]}")    fail2ban_write_jail_local; gum_pause ;;
      "${T[f2b_m_status]}")  fail2ban_status; gum_pause ;;
      "${T[f2b_m_unban]}")   fail2ban_unban_ip; gum_pause ;;
      "${T[back]}")          break ;;
    esac
  done
}
