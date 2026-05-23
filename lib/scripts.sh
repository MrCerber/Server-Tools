#!/usr/bin/env bash
# Utility scripts submenu — sourced by install-tui.sh

run_script() {
  local name="$1"
  local path="${SCRIPTS_DIR}/${name}"

  if [[ ! -f "$path" ]]; then
    if ! has_cmd curl && ! has_cmd wget; then
      warn "Script not found locally and neither curl nor wget is available."
      return 0
    fi
    require_internet_or_warn
    say "${T[scripts_downloading]}"
    _TMPDIR="$(mktemp -d -t mrcerber-scripts-XXXXXX)"
    if ! _download_file "${MOTD_BASE_URL}/scripts/${name}" "${_TMPDIR}/${name}"; then
      warn "Failed to download ${name}."
      _TMPDIR=""; return 0
    fi
    path="${_TMPDIR}/${name}"
  fi

  bash "$path"
  _TMPDIR=""
}

scripts_menu() {
  while true; do
    clear
    gum_header "${T[scripts_menu_title]}"

    local choice
    choice=$(gum choose --cursor="▶ " \
      "${T[scripts_m_cf]}" \
      "${T[scripts_m_bbr]}" \
      "${T[back]}") || break

    case "$choice" in
      "${T[scripts_m_cf]}")  run_script "cf_dns_manager.sh" ;;
      "${T[scripts_m_bbr]}") run_script "enable_bbr.sh"; gum_pause ;;
      "${T[back]}")          break ;;
    esac
  done
}
