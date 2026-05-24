#!/usr/bin/env bash
# gum UI helpers — sourced by install-tui.sh

# ── gum installer ─────────────────────────────────────────────────────────────
ensure_gum() {
  has_cmd gum && return 0
  printf "Installing gum (Charm TUI)...\n"
  if ! has_cmd curl; then
    apt-get install -y curl >/dev/null 2>&1 || true
  fi
  curl -fsSL https://repo.charm.sh/apt/gpg.key \
    | gpg --dearmor -o /usr/share/keyrings/charm.gpg
  echo "deb [signed-by=/usr/share/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" \
    > /etc/apt/sources.list.d/charm.list
  apt-get update -qq
  apt-get install -y gum
}

# ── Display helpers ───────────────────────────────────────────────────────────
gum_header() {
  local title="$1"
  local host; host="$(hostname -s 2>/dev/null || echo server)"
  echo
  gum style \
    --foreground 45 --bold \
    --border double --border-foreground 45 \
    --padding "1 4" \
    --align center \
    --width 60 \
    "${title}"$'\n'"$(gum style --foreground 240 "root@${host}")"
  echo
}

gum_section() {
  gum style --foreground 214 --bold "  ▸ $1"
}

gum_status_bar() {
  local ufw fail2ban
  ufw="$(_svc_badge_color ufw)"
  fail2ban="$(_svc_badge_color fail2ban)"
  printf "  \e[38;5;240m%s\e[0m\n" "${T[subtitle]}"
  printf "  UFW: %s    Fail2ban: %s\n\n" "$ufw" "$fail2ban"
}

# ── Interaction helpers ───────────────────────────────────────────────────────
gum_confirm() {
  gum confirm \
    --affirmative "${T[confirm_yes]}" \
    --negative "${T[confirm_no]}" \
    -- "$1"
}

gum_pause() {
  echo
  gum input --placeholder "${T[press_enter]}" > /dev/null 2>&1 || true
}

done_pause() {
  echo
  gum style \
    --foreground 82 --bold \
    --border rounded --border-foreground 238 \
    --padding "0 2" \
    "  ✓  ${T[done]}"
  echo
  gum input --placeholder "  ${T[press_enter]}" > /dev/null 2>&1 || true
}

gum_spin() {
  local title="$1"; shift
  log_action "CMD: $*"
  local _rc=0
  gum spin --title "$title" -- "$@" || _rc=$?
  if [[ $_rc -ne 0 ]]; then
    log_action "FAILED (exit ${_rc}): $*"
  fi
  return $_rc
}

gum_input() {
  gum input --placeholder "$1"
}
