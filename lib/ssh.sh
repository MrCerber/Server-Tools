#!/usr/bin/env bash
# SSH hardening functions — sourced by install-tui.sh

ssh_status() {
  gum style --foreground 45 --bold "  ${T[ssh_status_title]}"
  echo
  local port auth root_login printlastlog
  port="$(        grep -iE '^\s*Port\s+'                 "${SSHD_CONFIG}" 2>/dev/null | awk '{print $2}' | tail -1 || true)"
  auth="$(        grep -iE '^\s*PasswordAuthentication\s+' "${SSHD_CONFIG}" 2>/dev/null | awk '{print $2}' | tail -1 || true)"
  root_login="$(  grep -iE '^\s*PermitRootLogin\s+'       "${SSHD_CONFIG}" 2>/dev/null | awk '{print $2}' | tail -1 || true)"
  printlastlog="$(grep -iE '^\s*PrintLastLog\s+'          "${SSHD_CONFIG}" 2>/dev/null | awk '{print $2}' | tail -1 || true)"
  printf "  %-32s %s\n" "${T[ssh_port]}"        "${port:-22 (default)}"
  printf "  %-32s %s\n" "${T[ssh_pass_auth]}"   "${auth:-yes (default)}"
  printf "  %-32s %s\n" "${T[ssh_root_login]}"  "${root_login:-yes (default)}"
  printf "  %-32s %s\n" "${T[ssh_printlastlog]}" "${printlastlog:-yes (default)}"
}

ssh_disable_password_auth() {
  warn "${T[ssh_disable_pass_warn]}"
  gum_confirm "${T[ssh_disable_pass_confirm]}" || return 0
  _sshd_set_option "PasswordAuthentication" "no"
  _sshd_validate_and_reload
  log_action "ssh_disable_password_auth"
  say "${T[ssh_disable_pass_done]}"
}

ssh_restrict_root_login() {
  say "${T[ssh_restrict_root_info]}"
  gum_confirm "${T[os_continue]}" || return 0
  _sshd_set_option "PermitRootLogin" "prohibit-password"
  _sshd_validate_and_reload
  log_action "ssh_restrict_root_login"
  say "${T[ssh_restrict_root_done]}"
}

ssh_change_port() {
  local port
  while true; do
    port=$(gum_input "${T[ssh_port_prompt]}") || return 0
    _validate_port "$port" && break
    warn "${T[err_invalid_port]}"
  done

  gum_confirm "$(_t ssh_port_confirm "$port")" || return 0
  _sshd_set_option "Port" "$port"
  _sshd_validate_and_reload
  if has_cmd ufw && ufw status 2>/dev/null | grep -q "^Status: active"; then
    ufw allow "${port}/tcp" comment "SSH" >/dev/null
    say "$(_t ssh_port_ufw_added "$port")"
  fi
  log_action "ssh_change_port ${port}"
  say "$(_t ssh_port_done "$port")"
}

ssh_menu() {
  while true; do
    clear
    gum_header "${T[ssh_menu_title]}"

    local choice
    choice=$(gum choose --cursor="▶ " \
      "${T[ssh_m_status]}" \
      "${T[ssh_m_disable_pass]}" \
      "${T[ssh_m_restrict_root]}" \
      "${T[ssh_m_change_port]}" \
      "${T[back]}") || break

    case "$choice" in
      "${T[ssh_m_status]}")        ssh_status; gum_pause ;;
      "${T[ssh_m_disable_pass]}")  ssh_disable_password_auth; gum_pause ;;
      "${T[ssh_m_restrict_root]}") ssh_restrict_root_login; gum_pause ;;
      "${T[ssh_m_change_port]}")   ssh_change_port; gum_pause ;;
      "${T[back]}")                break ;;
    esac
  done
}
