#!/usr/bin/env bash
# Bootstrap-скрипт для TUI-версии MrCerber Server Tools
# Скачивает архив с main и запускает install-tui.sh
set -Eeuo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  printf "ERROR: Run as root (sudo bash get-tui.sh)\n" >&2
  exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

printf "Downloading MrCerber Server Tools (TUI edition)...\n"
curl -fsSL https://github.com/MrCerber/Server-Tools/archive/refs/heads/main.tar.gz \
  | tar -xz -C "$TMP"

bash "$TMP/Server-Tools-main/install-tui.sh"
