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
  echo
  gum style \
    --foreground 45 --bold \
    --border rounded --border-foreground 45 \
    --padding "0 2" \
    "$1"
  echo
}

gum_section() {
  gum style --foreground 81 --bold "  ── $1 ──"
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

gum_spin() {
  local title="$1"; shift
  gum spin --title "$title" -- "$@"
}

gum_input() {
  gum input --placeholder "$1"
}
