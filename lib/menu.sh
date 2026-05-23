#!/usr/bin/env bash
# fzf menu helpers — sourced by install-tui.sh

# ── fzf installer ─────────────────────────────────────────────────────────────
ensure_fzf() {
  has_cmd fzf && return 0
  printf "Installing fzf...\n"
  apt-get install -y fzf >/dev/null 2>&1 \
    || die "Failed to install fzf. Run: apt-get install fzf"
}

# ── Menu picker ───────────────────────────────────────────────────────────────
# Usage : _fzf_pick <items_array_name> <header_text>
# Items : "id|label|description"
# Returns: selected id via stdout; empty on Esc / Ctrl+C
_fzf_pick() {
  local -n _fp="$1"
  local _hdr="${2:-}"

  local _input="" _i
  for _i in "${_fp[@]}"; do
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
    2>/dev/null | cut -f1
}
