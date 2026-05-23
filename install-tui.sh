#!/usr/bin/env bash
# MrCerber Server Tools — TUI Edition (gum)
# Requirements: root, Ubuntu/Debian
# Original: install.sh (kept intact)

# Ensure 256-color support for SSH clients that don't advertise it (e.g. MobaXterm)
export TERM="${TERM:-xterm-256color}"
export COLORTERM="${COLORTERM:-truecolor}"

set -Eeuo pipefail

# ── Globals ───────────────────────────────────────────────────────────────────
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
_TMPDIR=""

# ── Cleanup trap ──────────────────────────────────────────────────────────────
_cleanup() {
  local rc=$?
  [[ -n "$_TMPDIR" ]] && rm -rf "$_TMPDIR"
  (( rc != 0 )) && printf "\nScript exited with error (code %d). Check %s\n" \
    "$rc" "${LOG_FILE}" >&2 || true
}
trap _cleanup EXIT

# ── Load libraries ────────────────────────────────────────────────────────────
# shellcheck source=lib/utils.sh
source "${SCRIPT_DIR}/lib/utils.sh"
# shellcheck source=lib/ui.sh
source "${SCRIPT_DIR}/lib/ui.sh"
# shellcheck source=lib/menu.sh
source "${SCRIPT_DIR}/lib/menu.sh"
# shellcheck source=lib/lang.sh
source "${SCRIPT_DIR}/lib/lang.sh"
# shellcheck source=lib/system.sh
source "${SCRIPT_DIR}/lib/system.sh"
# shellcheck source=lib/motd.sh
source "${SCRIPT_DIR}/lib/motd.sh"
# shellcheck source=lib/ssh.sh
source "${SCRIPT_DIR}/lib/ssh.sh"
# shellcheck source=lib/ufw.sh
source "${SCRIPT_DIR}/lib/ufw.sh"
# shellcheck source=lib/fail2ban.sh
source "${SCRIPT_DIR}/lib/fail2ban.sh"
# shellcheck source=lib/docker.sh
source "${SCRIPT_DIR}/lib/docker.sh"
# shellcheck source=lib/scripts.sh
source "${SCRIPT_DIR}/lib/scripts.sh"

# ── Main menu ─────────────────────────────────────────────────────────────────
main_menu() {
  local -a _SECTIONS=(
    "quick|⚡ ${T[sec_quick]}|${T[d_sec_quick]}"
    "system|🖥️  ${T[sec_system]}|${T[d_sec_system]}"
    "users|👤 ${T[sec_users]}|${T[d_sec_users]}"
    "security|🛡️  ${T[sec_security]}|${T[d_sec_security]}"
    "appearance|🎨 ${T[sec_appearance]}|${T[d_sec_appearance]}"
    "services|📦 ${T[sec_services]}|${T[d_sec_services]}"
    "utils|🔧 ${T[sec_utils]}|${T[d_sec_utils]}"
    "exit|🚪 ${T[exit]}|"
  )
  local -a _ITEMS_QUICK=(
    "full_setup|${T[m_full_setup]}|${T[d_full_setup]}"
    "alias|${T[m_alias]}|${T[d_alias]}"
    "back|← ${T[back]}|"
  )
  local -a _ITEMS_SYSTEM=(
    "update|${T[m_update]}|${T[d_update]}"
    "packages|${T[m_packages]}|${T[d_packages]}"
    "autoupdates|${T[m_autoupdates]}|${T[d_autoupdates]}"
    "swap|${T[m_swap]}|${T[d_swap]}"
    "back|← ${T[back]}|"
  )
  local -a _ITEMS_USERS=(
    "sudo_user|${T[m_sudo_user]}|${T[d_sudo_user]}"
    "back|← ${T[back]}|"
  )
  local -a _ITEMS_SECURITY=(
    "ssh|${T[m_ssh]}|${T[d_ssh]}"
    "ufw|${T[m_ufw]}|${T[d_ufw]}"
    "fail2ban|${T[m_fail2ban]}|${T[d_fail2ban]}"
    "hardening|${T[m_hardening]}|${T[d_hardening]}"
    "back|← ${T[back]}|"
  )
  local -a _ITEMS_APPEARANCE=(
    "motd_install|${T[m_motd_install]}|${T[d_motd_install]}"
    "motd_restore|${T[m_motd_restore]}|${T[d_motd_restore]}"
    "motd_preview|${T[m_motd_preview]}|${T[d_motd_preview]}"
    "back|← ${T[back]}|"
  )
  local -a _ITEMS_SERVICES=(
    "docker|${T[m_docker]}|${T[d_docker]}"
    "1panel|${T[m_1panel]}|${T[d_1panel]}"
    "back|← ${T[back]}|"
  )
  local -a _ITEMS_UTILS=(
    "aliases|${T[m_aliases]}|${T[d_aliases]}"
    "apt_clean|${T[m_apt_clean]}|${T[d_apt_clean]}"
    "cron|${T[m_cron]}|${T[d_cron]}"
    "scripts|${T[m_scripts]}|${T[d_scripts]}"
    "log|${T[m_log]}|${T[d_log]}"
    "back|← ${T[back]}|"
  )

  while true; do
    local _ufw_b _f2b_b
    _ufw_b="$(_svc_badge_color ufw)"
    _f2b_b="$(_svc_badge_color fail2ban)"
    local _main_hdr
    _main_hdr="$(printf '\e[38;5;45m\e[1m%s\e[0m  \e[38;5;240m|\e[0m  root@%s\n  UFW: %s    Fail2ban: %s' \
      "${T[title]}" "$(hostname -s 2>/dev/null || echo server)" "$_ufw_b" "$_f2b_b")"

    local _section_id
    _section_id=$(_fzf_pick _SECTIONS "$_main_hdr") || exit 0
    [[ -z "$_section_id" || "$_section_id" == "exit" ]] && exit 0

    local _sec_lbl _s
    for _s in "${_SECTIONS[@]}"; do
      [[ "${_s%%|*}" == "$_section_id" ]] && { _sec_lbl="${_s#*|}"; _sec_lbl="${_sec_lbl%%|*}"; break; }
    done

    local _section_hdr
    _section_hdr="$(printf '\e[38;5;45m\e[1m%s\e[0m  \e[38;5;238m›\e[0m  %s' "${T[title]}" "$_sec_lbl")"

    local -n _cur_items="_ITEMS_${_section_id^^}"

    while true; do
      local _action
      _action=$(_fzf_pick _cur_items "$_section_hdr") || break
      [[ -z "$_action" || "$_action" == "back" ]] && break

      case "$_action" in
        full_setup)   full_base_setup;           gum_pause ;;
        alias)        create_script_alias;        gum_pause ;;
        update)       apt_update_upgrade;         gum_pause ;;
        packages)     install_base_packages;      gum_pause ;;
        autoupdates)  enable_auto_updates;        gum_pause ;;
        swap)         setup_swap;                 gum_pause ;;
        sudo_user)    create_sudo_user;           gum_pause ;;
        ssh)          ssh_menu ;;
        ufw)          ufw_menu ;;
        fail2ban)     fail2ban_menu ;;
        hardening)    apply_sysctl_hardening;     gum_pause ;;
        motd_install) install_custom_motd;        gum_pause ;;
        motd_restore) restore_default_motd;       gum_pause ;;
        motd_preview) preview_motd;               gum_pause ;;
        docker)       install_docker;             gum_pause ;;
        1panel)       install_1panel;             gum_pause ;;
        aliases)      install_aliases;            gum_pause ;;
        apt_clean)    cleanup_apt;                gum_pause ;;
        cron)         setup_auto_reboot_cron;     gum_pause ;;
        scripts)      scripts_menu ;;
        log)          show_log;                   gum_pause ;;
      esac
    done
  done
}

# ── Entrypoint ────────────────────────────────────────────────────────────────
require_root
ensure_dirs
ensure_gum
ensure_fzf
choose_language
check_os_supported
main_menu
