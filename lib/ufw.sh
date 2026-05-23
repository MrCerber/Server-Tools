#!/usr/bin/env bash
# UFW firewall functions — sourced by install-tui.sh

ufw_status() {
  ufw status verbose 2>/dev/null || say "UFW not available."
}

ufw_basic_hardening() {
  log_action "ufw_basic_hardening"
  ufw default deny incoming
  ufw default allow outgoing
  say "${T[ufw_defaults_done]}"
}

ufw_allow_ssh()        { ufw allow 22/tcp;  log_action "ufw allow 22/tcp"; }
ufw_allow_http_https() { ufw allow 80/tcp; ufw allow 443/tcp; log_action "ufw allow 80+443"; }

ufw_allow_custom() {
  local port
  while true; do
    port=$(gum_input "${T[ufw_port_prompt]}") || return 0
    _validate_port "$port" && break
    warn "${T[err_invalid_port]}"
  done

  local proto
  proto=$(gum_input "${T[ufw_proto_prompt]}") || proto="tcp"
  proto="${proto:-tcp}"

  case "${proto,,}" in
    tcp|udp)
      ufw allow "${port}/${proto,,}"
      log_action "ufw allow ${port}/${proto,,}"
      ;;
    both)
      ufw allow "${port}/tcp"
      ufw allow "${port}/udp"
      log_action "ufw allow ${port}/tcp+udp"
      ;;
    *)
      warn "${T[invalid_choice]}"; return 0 ;;
  esac
}

ufw_allow_from_ip() {
  local src_ip
  while true; do
    src_ip=$(gum_input "${T[ufw_ip_prompt]}") || return 0
    [[ -n "$src_ip" ]] || { warn "${T[cannot_be_empty]}"; continue; }
    _validate_ipv4 "$src_ip" && break
    warn "${T[err_invalid_ip]}"
  done

  local port
  while true; do
    port=$(gum_input "${T[ufw_port2_prompt]}") || return 0
    _validate_port "$port" && break
    warn "${T[err_invalid_port]}"
  done

  local proto
  proto=$(gum_input "${T[ufw_proto_prompt]}") || proto="tcp"
  proto="${proto:-tcp}"

  case "${proto,,}" in
    tcp|udp)
      ufw allow from "$src_ip" to any port "$port" proto "${proto,,}"
      log_action "ufw allow from ${src_ip} port ${port} proto ${proto,,}"
      ;;
    both)
      ufw allow from "$src_ip" to any port "$port" proto tcp
      ufw allow from "$src_ip" to any port "$port" proto udp
      log_action "ufw allow from ${src_ip} port ${port} proto tcp+udp"
      ;;
    *)
      warn "${T[invalid_choice]}"; return 0 ;;
  esac
}

ufw_delete_rule() {
  say "${T[ufw_delete_title]}"
  ufw status numbered 2>/dev/null || true
  echo

  local num
  num=$(gum_input "${T[ufw_delete_prompt]}") || return 0
  [[ "$num" =~ ^[0-9]+$ ]] || { warn "${T[invalid_choice]}"; return 0; }
  gum_confirm "$(_t ufw_delete_confirm "$num")" || return 0
  yes | ufw delete "$num"
  log_action "ufw delete rule ${num}"
}

ufw_enable() {
  log_action "ufw enable"
  ufw --force enable
  systemctl enable --now ufw >/dev/null 2>&1 || true
}

ufw_disable() {
  log_action "ufw disable"
  ufw disable
}

ufw_reset() {
  gum_confirm "${T[ufw_reset_confirm]}" || return 0
  log_action "ufw reset"
  ufw --force reset
}

ufw_menu() {
  while true; do
    clear
    gum_header "${T[ufw_menu_title]}"

    local choice
    choice=$(gum choose --cursor="▶ " --height=15 \
      "${T[ufw_m_status]}" \
      "${T[ufw_m_defaults]}" \
      "${T[ufw_m_ssh]}" \
      "${T[ufw_m_http]}" \
      "${T[ufw_m_custom]}" \
      "${T[ufw_m_from_ip]}" \
      "${T[ufw_m_delete]}" \
      "${T[ufw_m_enable]}" \
      "${T[ufw_m_disable]}" \
      "${T[ufw_m_reset]}" \
      "${T[back]}") || break

    case "$choice" in
      "${T[ufw_m_status]}")   ufw_status; gum_pause ;;
      "${T[ufw_m_defaults]}") ufw_basic_hardening; gum_pause ;;
      "${T[ufw_m_ssh]}")      ufw_allow_ssh; gum_pause ;;
      "${T[ufw_m_http]}")     ufw_allow_http_https; gum_pause ;;
      "${T[ufw_m_custom]}")   ufw_allow_custom; gum_pause ;;
      "${T[ufw_m_from_ip]}")  ufw_allow_from_ip; gum_pause ;;
      "${T[ufw_m_delete]}")   ufw_delete_rule; gum_pause ;;
      "${T[ufw_m_enable]}")   ufw_enable; gum_pause ;;
      "${T[ufw_m_disable]}")  ufw_disable; gum_pause ;;
      "${T[ufw_m_reset]}")    ufw_reset; gum_pause ;;
      "${T[back]}")           break ;;
    esac
  done
}
