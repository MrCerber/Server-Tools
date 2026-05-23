#!/usr/bin/env bash
# MrCerber Server Tools — TUI Edition (gum)
# Requirements: root, Ubuntu/Debian
# Original: install.sh (kept intact)

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
  while true; do
    clear
    gum_header "${T[title]}"
    gum style --foreground 240 "  ${T[subtitle]}"
    gum style --foreground 240 "  UFW: $(_svc_badge ufw)    Fail2ban: $(_svc_badge fail2ban)"
    echo

    local choice
    choice=$(gum choose --cursor="▶ " --height=30 \
      "  ─── ${T[sec_quick]} ───" \
      "  ${T[m_alias]}" \
      "  ─── ${T[sec_system]} ───" \
      "  ${T[m_full_setup]}" \
      "  ${T[m_update]}" \
      "  ${T[m_packages]}" \
      "  ${T[m_autoupdates]}" \
      "  ${T[m_sudo_user]}" \
      "  ${T[m_swap]}" \
      "  ─── ${T[sec_motd_ssh]} ───" \
      "  ${T[m_motd_install]}" \
      "  ${T[m_motd_restore]}" \
      "  ${T[m_motd_preview]}" \
      "  ${T[m_ssh]}" \
      "  ─── ${T[sec_security]} ───" \
      "  ${T[m_ufw]}" \
      "  ${T[m_fail2ban]}" \
      "  ${T[m_hardening]}" \
      "  ─── ${T[sec_panels]} ───" \
      "  ${T[m_docker]}" \
      "  ${T[m_1panel]}" \
      "  ─── ${T[sec_extras]} ───" \
      "  ${T[m_aliases]}" \
      "  ${T[m_apt_clean]}" \
      "  ${T[m_cron]}" \
      "  ${T[m_log]}" \
      "  ─── ${T[sec_scripts]} ───" \
      "  ${T[m_scripts]}" \
      "  ${T[exit]}") || continue

    # Strip leading "  "
    choice="${choice#"  "}"

    case "$choice" in
      "─── "*) continue ;;
      "${T[m_alias]}")        create_script_alias; gum_pause ;;
      "${T[m_full_setup]}") full_base_setup; gum_pause ;;
      "${T[m_update]}")       apt_update_upgrade; gum_pause ;;
      "${T[m_packages]}")     install_base_packages; gum_pause ;;
      "${T[m_autoupdates]}") enable_auto_updates; gum_pause ;;
      "${T[m_sudo_user]}")   create_sudo_user; gum_pause ;;
      "${T[m_swap]}")         setup_swap; gum_pause ;;
      "${T[m_motd_install]}") install_custom_motd; gum_pause ;;
      "${T[m_motd_restore]}") restore_default_motd; gum_pause ;;
      "${T[m_motd_preview]}") preview_motd; gum_pause ;;
      "${T[m_ssh]}")          ssh_menu ;;
      "${T[m_ufw]}")          ufw_menu ;;
      "${T[m_fail2ban]}")     fail2ban_menu ;;
      "${T[m_hardening]}")    apply_sysctl_hardening; gum_pause ;;
      "${T[m_docker]}")       install_docker; gum_pause ;;
      "${T[m_1panel]}")       install_1panel; gum_pause ;;
      "${T[m_aliases]}")      install_aliases; gum_pause ;;
      "${T[m_apt_clean]}")    cleanup_apt; gum_pause ;;
      "${T[m_cron]}")         setup_auto_reboot_cron; gum_pause ;;
      "${T[m_log]}")          show_log; gum_pause ;;
      "${T[m_scripts]}")      scripts_menu ;;
      "${T[exit]}")           exit 0 ;;
    esac
  done
}

# ── Entrypoint ────────────────────────────────────────────────────────────────
require_root
ensure_dirs
ensure_gum
choose_language
check_os_supported
main_menu
