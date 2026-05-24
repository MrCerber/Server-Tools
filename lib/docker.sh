#!/usr/bin/env bash
# Docker and 1Panel installation — sourced by install-tui.sh

install_docker() {
  log_action "install_docker"
  if has_cmd docker; then
    say "$(_t docker_installed "$(docker --version 2>/dev/null)")"
    gum_confirm "${T[docker_reinstall]}" || return 0
  fi

  warn "${T[docker_warn]}"
  require_internet_or_warn

  local tmp; tmp=$(mktemp /tmp/docker-install-XXXXX.sh)
  if has_cmd curl; then
    gum_spin "${T[docker_downloading]}" curl -fsSL --max-time 60 "https://get.docker.com" -o "$tmp" \
      || die "${T[err_download_failed]}: https://get.docker.com"
  elif has_cmd wget; then
    gum_spin "${T[docker_downloading]}" wget -qO "$tmp" "https://get.docker.com" \
      || die "${T[err_download_failed]}: https://get.docker.com"
  else
    die "Neither curl nor wget is available."
  fi

  local sha; sha="$(sha256sum "$tmp" | awk '{print $1}')"
  say "$(_t docker_sha256 "$sha")"

  if ! gum_confirm "${T[docker_confirm]}"; then
    rm -f "$tmp"; return 0
  fi

  log_action "install_docker START"
  bash "$tmp" 2>&1 | tee -a "${LOG_FILE}" || {
    log_action "install_docker SCRIPT FAILED"
    rm -f "$tmp"
    die "${T[docker_install_fail]}"
  }
  rm -f "$tmp"
  log_action "install_docker END"
  say "$(_t docker_done "$(docker --version 2>/dev/null || echo 'unknown')")"
}

install_1panel() {
  log_action "install_1panel"
  warn "${T[1panel_warn]}"
  gum_confirm "${T[1panel_confirm]}" || return 0

  require_internet_or_warn

  local tmp; tmp=$(mktemp /tmp/1panel-install-XXXXX.sh)
  local _url="https://resource.1panel.pro/v2/quick_start.sh"
  if has_cmd curl; then
    gum_spin "${T[1panel_downloading]}" curl -fsSL --max-time 60 "$_url" -o "$tmp" \
      || die "${T[err_download_failed]}: ${_url}"
  elif has_cmd wget; then
    gum_spin "${T[1panel_downloading]}" wget -qO "$tmp" "$_url" \
      || die "${T[err_download_failed]}: ${_url}"
  else
    die "Neither curl nor wget is available."
  fi

  local sha; sha="$(sha256sum "$tmp" | awk '{print $1}')"
  say "$(_t docker_sha256 "$sha")"

  if ! gum_confirm "${T[1panel_confirm]}"; then
    rm -f "$tmp"; return 0
  fi

  log_action "install_1panel START"
  bash "$tmp" 2>&1 | tee -a "${LOG_FILE}" || {
    log_action "install_1panel SCRIPT FAILED"
    rm -f "$tmp"
    die "${T[docker_install_fail]}"
  }
  rm -f "$tmp"
  log_action "install_1panel END"
}
