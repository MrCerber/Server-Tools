#!/usr/bin/env bash
# Common utilities — sourced by install-tui.sh

# ── Root check + lock ─────────────────────────────────────────────────────────
require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    printf "ERROR: This script must be run as root.\n" >&2
    exit 1
  fi
  # shellcheck disable=SC2093
  exec 9>/var/run/mrcerber-bootstrap.lock
  flock -n 9 2>/dev/null || {
    printf "ERROR: Another instance of this script is already running.\n" >&2
    exit 1
  }
}

ensure_dirs() { mkdir -p "${BACKUP_DIR}"; }

# ── Output ────────────────────────────────────────────────────────────────────
say()  { printf "%s\n" "$*"; }
warn() { printf "WARNING: %s\n" "$*" >&2; }
die()  { printf "ERROR: %s\n" "$*" >&2; exit 1; }

has_cmd() { command -v "$1" >/dev/null 2>&1; }

# ── Translation helper ────────────────────────────────────────────────────────
# Usage: _t key [printf-args...]
_t() {
  local key="$1"; shift
  # shellcheck disable=SC2059
  printf "${T[$key]}" "$@"
}

# ── Logging ───────────────────────────────────────────────────────────────────
log_action() {
  local ts; ts="$(date '+%Y-%m-%d %H:%M:%S')"
  printf "[%s] %s\n" "$ts" "$1" >> "${LOG_FILE}"
}

show_log() {
  if [[ -f "${LOG_FILE}" ]]; then
    gum pager < "${LOG_FILE}"
  else
    warn "${T[log_empty]}"
  fi
}

# ── Backup ────────────────────────────────────────────────────────────────────
backup_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  local ts safe_name dest
  ts="$(date +%Y%m%d-%H%M%S)"
  safe_name="${f//\//__}"
  dest="${BACKUP_DIR}/${safe_name}.${ts}.bak"
  cp -a "$f" "$dest"
}

backup_dir_tar() {
  local d="$1"
  [[ -d "$d" ]] || return 0
  local ts safe_name dest
  ts="$(date +%Y%m%d-%H%M%S)"
  safe_name="${d//\//__}"
  dest="${BACKUP_DIR}/${safe_name}.${ts}.tar.gz"
  tar -czf "$dest" -C "$(dirname "$d")" "$(basename "$d")"
}

# ── SSH config helper ─────────────────────────────────────────────────────────
# Single function replaces 4 duplicate sed+sshd blocks from original install.sh
_sshd_set_option() {
  local key="$1" value="$2"
  backup_file "${SSHD_CONFIG}" || die "${T[err_backup_failed]}"
  if grep -qiE "^\s*${key}\s+" "${SSHD_CONFIG}"; then
    sed -i "s|^\s*${key}\s.*|${key} ${value}|I" "${SSHD_CONFIG}"
  else
    printf "\n%s %s\n" "${key}" "${value}" >> "${SSHD_CONFIG}"
  fi
}

_sshd_validate_and_reload() {
  if ! sshd -t -f "${SSHD_CONFIG}" 2>/dev/null; then
    local latest_bak
    # Sort by embedded YYYYMMDD-HHMMSS timestamp — lexicographic order is chronological
    latest_bak="$(find "${BACKUP_DIR}" -maxdepth 1 -name "*sshd_config*" | sort | tail -1)"
    [[ -n "$latest_bak" ]] && cp "$latest_bak" "${SSHD_CONFIG}"
    die "${T[err_sshd_invalid]}"
  fi
  systemctl reload ssh >/dev/null 2>&1 \
    || systemctl reload sshd >/dev/null 2>&1 \
    || warn "SSH reload failed — run: systemctl restart ssh"
}

# ── Download helper ───────────────────────────────────────────────────────────
_download_file() {
  local url="$1" dest="$2"
  if has_cmd curl; then
    curl -fsSL --max-time 30 "$url" -o "$dest" \
      || die "${T[err_download_failed]}: $url"
  elif has_cmd wget; then
    wget -qO "$dest" "$url" \
      || die "${T[err_download_failed]}: $url"
  else
    die "Neither curl nor wget is available."
  fi
}

# ── Validators ────────────────────────────────────────────────────────────────
_validate_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 ))
}

_validate_ipv4() {
  [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/([0-9]|[1-2][0-9]|3[0-2]))?$ ]]
}

_validate_ssh_pubkey() {
  local tmp; tmp=$(mktemp)
  printf "%s\n" "$1" > "$tmp"
  ssh-keygen -l -f "$tmp" >/dev/null 2>&1
  local rc=$?
  rm -f "$tmp"
  return $rc
}

# ── Service status badge ──────────────────────────────────────────────────────
_svc_badge() {
  if systemctl is-active --quiet "$1" 2>/dev/null; then
    printf "active"
  elif systemctl is-enabled --quiet "$1" 2>/dev/null; then
    printf "stopped"
  else
    printf "inactive"
  fi
}

# ── Internet / OS checks ──────────────────────────────────────────────────────
check_internet() {
  if ! ping -c1 -W3 8.8.8.8 >/dev/null 2>&1; then
    warn "${T[no_internet]}"
    gum_confirm "${T[os_continue]}" || return 1
  fi
  return 0
}

require_internet_or_warn() { check_internet || true; }

check_os_supported() {
  [[ -f /etc/os-release ]] || { warn "Cannot detect OS. Proceeding anyway."; return 0; }
  local id id_like pretty
  id="$(. /etc/os-release && echo "${ID:-}")"
  id_like="$(. /etc/os-release && echo "${ID_LIKE:-}")"
  pretty="$(. /etc/os-release && echo "${PRETTY_NAME:-unknown}")"
  if [[ "$id" == "ubuntu" || "$id" == "debian" \
     || "$id_like" == *"debian"* || "$id_like" == *"ubuntu"* ]]; then
    log_action "OS check passed: ${pretty}"
    return 0
  fi
  warn "${T[os_not_ubuntu]} Detected: ${id} (${pretty})."
  gum_confirm "${T[os_continue]}" || exit 1
}
