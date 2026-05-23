#!/usr/bin/env bash
# Docker and 1Panel installation — sourced by install-tui.sh

install_docker() {
  if has_cmd docker; then
    say "$(_t docker_installed "$(docker --version 2>/dev/null)")"
    gum_confirm "${T[docker_reinstall]}" || return 0
  fi

  warn "${T[docker_warn]}"
  require_internet_or_warn

  local tmp; tmp=$(mktemp /tmp/docker-install-XXXXX.sh)
  gum_spin "${T[docker_downloading]}" _download_file "https://get.docker.com" "$tmp"

  local sha; sha="$(sha256sum "$tmp" | awk '{print $1}')"
  say "$(_t docker_sha256 "$sha")"

  if ! gum_confirm "${T[docker_confirm]}"; then
    rm -f "$tmp"; return 0
  fi

  log_action "install_docker START"
  bash "$tmp"
  rm -f "$tmp"
  log_action "install_docker END"
  say "$(_t docker_done "$(docker --version 2>/dev/null || echo 'unknown')")"
}

install_1panel() {
  warn "${T[1panel_warn]}"
  gum_confirm "${T[1panel_confirm]}" || return 0

  require_internet_or_warn

  local tmp; tmp=$(mktemp /tmp/1panel-install-XXXXX.sh)
  gum_spin "${T[1panel_downloading]}" \
    _download_file "https://resource.1panel.pro/v2/quick_start.sh" "$tmp"

  local sha; sha="$(sha256sum "$tmp" | awk '{print $1}')"
  say "$(_t docker_sha256 "$sha")"

  if ! gum_confirm "${T[1panel_confirm]}"; then
    rm -f "$tmp"; return 0
  fi

  log_action "install_1panel START"
  bash "$tmp"
  rm -f "$tmp"
  log_action "install_1panel END"
}
