#!/usr/bin/env bash
# MOTD management — sourced by install-tui.sh

_disable_default_motd_scripts() {
  local f base
  while IFS= read -r -d '' f; do
    base="$(basename "$f")"
    [[ "$base" == "99-mrcerber" || "$base" == "logo.txt" ]] && continue
    [[ -x "$f" ]] && chmod -x "$f" || true
  done < <(find "${MOTD_DIR}" -maxdepth 1 -type f -print0)
}

_enable_default_motd_scripts() {
  local defaults=(
    "00-header" "10-help-text" "50-motd-news" "50-landscape-sysinfo"
    "85-fwupd" "90-updates-available" "91-contract-ua-esm-status"
    "91-release-upgrade" "92-unattended-upgrades" "95-hwe-eol"
    "97-overlayroot" "98-fsck-at-reboot"
  )
  local base
  for base in "${defaults[@]}"; do
    [[ -f "${MOTD_DIR}/${base}" ]] && chmod +x "${MOTD_DIR}/${base}" || true
  done
}

install_custom_motd() {
  local motd_99_src="${CUSTOM_MOTD_99_SRC}"
  local motd_logo_src="${CUSTOM_MOTD_LOGO_SRC}"

  if [[ ! -f "${motd_99_src}" || ! -f "${motd_logo_src}" ]]; then
    if ! has_cmd curl && ! has_cmd wget; then
      die "${T[motd_no_curl_wget]}"
    fi
    require_internet_or_warn
    say "${T[motd_downloading]}"
    _TMPDIR="$(mktemp -d -t mrcerber-motd-XXXXXX)"
    if [[ ! -f "${motd_99_src}" ]]; then
      _download_file "${MOTD_BASE_URL}/99-mrcerber" "${_TMPDIR}/99-mrcerber"
      motd_99_src="${_TMPDIR}/99-mrcerber"
    fi
    if [[ ! -f "${motd_logo_src}" ]]; then
      _download_file "${MOTD_BASE_URL}/logo.txt" "${_TMPDIR}/logo.txt"
      motd_logo_src="${_TMPDIR}/logo.txt"
    fi
  fi

  [[ -f "${motd_99_src}" ]]   || die "Missing custom file: ${motd_99_src}"
  [[ -f "${motd_logo_src}" ]] || die "Missing custom file: ${motd_logo_src}"

  log_action "install_custom_motd"
  backup_dir_tar "${MOTD_DIR}"
  install -m 0755 "${motd_99_src}"   "${MOTD_DIR}/99-mrcerber"
  install -m 0644 "${motd_logo_src}" "${MOTD_DIR}/logo.txt"
  _disable_default_motd_scripts
  _sshd_set_option "PrintLastLog" "no"
  _sshd_validate_and_reload
  _TMPDIR=""
  say "${T[motd_installed]}"
}

restore_default_motd() {
  log_action "restore_default_motd"
  backup_dir_tar "${MOTD_DIR}"
  [[ -f "${MOTD_DIR}/99-mrcerber" ]] && rm -f "${MOTD_DIR}/99-mrcerber"
  [[ -f "${MOTD_DIR}/logo.txt" ]]    && rm -f "${MOTD_DIR}/logo.txt"
  _enable_default_motd_scripts
  _sshd_set_option "PrintLastLog" "yes"
  _sshd_validate_and_reload
  say "${T[motd_restored]}"
}

preview_motd() {
  gum style --foreground 45 --bold "  ${T[motd_preview_title]}"
  echo
  run-parts "${MOTD_DIR}" 2>/dev/null || true
}
