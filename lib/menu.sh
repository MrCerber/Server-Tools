#!/usr/bin/env bash
# fzf menu helpers — sourced by install-tui.sh

# ── fzf installer ─────────────────────────────────────────────────────────────
ensure_fzf() {
  local _min="0.27"

  _fzf_ok() {
    has_cmd fzf || return 1
    local v; v=$(fzf --version 2>/dev/null | awk '{print $1}')
    # Returns 0 if installed version >= _min
    [[ "$(printf '%s\n%s\n' "$_min" "$v" | sort -V | head -1)" == "$_min" ]]
  }

  _fzf_ok && return 0

  printf "Installing fzf...\n"
  apt-get install -y fzf >/dev/null 2>&1 || true
  _fzf_ok && return 0

  # apt version too old (Ubuntu 20.04 ships 0.20) — download static binary
  printf "apt fzf is too old; downloading latest binary...\n"
  local arch
  case "$(uname -m)" in
    x86_64)  arch="linux_amd64" ;;
    aarch64) arch="linux_arm64" ;;
    armv7l)  arch="linux_armv7" ;;
    *)       die "fzf: unsupported architecture: $(uname -m)" ;;
  esac
  local url
  url=$(curl -fsSL "https://api.github.com/repos/junegunn/fzf/releases/latest" \
    | grep '"browser_download_url"' \
    | grep -E "${arch}\.tar\.gz\"" \
    | head -1 | cut -d'"' -f4)
  [[ -n "$url" ]] || die "Could not determine fzf download URL. Install manually."
  curl -fsSL "$url" | tar -xz -C /usr/local/bin/ fzf \
    || die "Failed to install fzf binary."
}

# ── Menu picker ───────────────────────────────────────────────────────────────
# Usage : _fzf_pick <header_text> <item> [item...]
# Items : "id|label|description"
# Returns: selected id via stdout; empty on Esc / Ctrl+C
_fzf_pick() {
  local _hdr="${1:-}"
  shift

  local _input="" _i
  for _i in "$@"; do
    local _id="${_i%%|*}"
    local _rest="${_i#*|}"
    local _lbl="${_rest%%|*}"
    local _desc="${_rest#*|}"
    _input+="${_id}"$'\t'"${_lbl}"$'\t'"${_desc}"$'\n'
  done

  printf '%s' "$_input" | fzf \
    --ansi \
    --no-sort \
    --no-info \
    --delimiter=$'\t' \
    --with-nth=2 \
    --prompt="  ▶  " \
    --pointer="▶" \
    --color='pointer:45,prompt:45,hl+:45,fg+:15,bg+:236,preview-bg:234,preview-fg:244,border:238,header:45,gutter:-1' \
    --header="$_hdr" \
    --header-first \
    --preview='l=$(printf "%s" {} | cut -f2); d=$(printf "%s" {} | cut -f3); printf "\n  \033[1m%s\033[0m\n\n  \033[38;5;244m%s\033[0m\n" "$l" "$d"' \
    --preview-window='bottom:5:wrap' \
    --bind='esc:abort' \
    2>>"${LOG_FILE:-/tmp/mrcerber-fzf.log}" | cut -f1
}
