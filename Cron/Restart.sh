#!/bin/bash

set -euo pipefail

# ================= CONFIG =================
REBOOT_DELAY_MIN=5
REASON_DEFAULT="Automatic reboot required after system updates"
LOG_PREFIX="[AUTO-REBOOT]"
HISTORY_FILE="/var/log/reboot-history.log"
MOTD_FILE="/etc/motd"
REBOOT_FLAG="/var/run/reboot-required"
REASON_FILE="/var/run/reboot-required.pkgs"
LOCK_FILE="/var/run/restart-scheduler.lock"
# ==========================================

# Prevent concurrent cron runs
exec 9>"$LOCK_FILE"
flock -n 9 || { echo "$LOG_PREFIX Already running — skipping"; exit 0; }

now() {
  date '+%Y-%m-%d %H:%M:%S'
}

# Validate config
if ! [[ "$REBOOT_DELAY_MIN" =~ ^[0-9]+$ ]]; then
  echo "ERROR: REBOOT_DELAY_MIN must be a non-negative integer" >&2
  exit 1
fi

echo "========================================"
echo "$LOG_PREFIX Cron started at: $(now)"

# ---- Check if reboot is required ----
if [ ! -f "$REBOOT_FLAG" ]; then
  echo "$LOG_PREFIX No reboot required"
  echo "$LOG_PREFIX Cron finished at: $(now)"
  exit 0
fi

echo "$LOG_PREFIX Reboot-required flag detected"

# ---- Determine reason ----
if [ -f "$REASON_FILE" ]; then
  REASON_PACKAGES=$(tr '\n' ' ' < "$REASON_FILE")
  REASON="Kernel / system packages updated: $REASON_PACKAGES"
else
  REASON="$REASON_DEFAULT"
fi

echo "$LOG_PREFIX Reason: $REASON"

# ---- Calculate reboot time ----
REBOOT_TIME="$(date -d "+$REBOOT_DELAY_MIN minutes" '+%Y-%m-%d %H:%M:%S')"

echo "$LOG_PREFIX Reboot scheduled in $REBOOT_DELAY_MIN minutes"
echo "$LOG_PREFIX Scheduled time: $REBOOT_TIME"

# ---- Write MOTD for next login ----
# Single-quoted delimiter: $REBOOT_TIME and $REASON are written literally below
#   then substituted via printf to avoid injection from the reason file
printf 'Last system reboot was scheduled automatically.\nTime: %s\nReason: %s\n' \
  "$REBOOT_TIME" "$REASON" > "$MOTD_FILE"

# ---- Append reboot history ----
echo "$(now) | Scheduled reboot at $REBOOT_TIME | Reason: $REASON" >> "$HISTORY_FILE"

# ---- Schedule reboot (systemd managed) ----
if ! shutdown -r "+$REBOOT_DELAY_MIN" "$REASON" 2>/dev/null; then
  echo "$(now) | ERROR: shutdown command failed" >> "$HISTORY_FILE"
  echo "$LOG_PREFIX ERROR: shutdown command failed" >&2
  exit 1
fi

echo "$LOG_PREFIX Shutdown command issued"
echo "$LOG_PREFIX Cron finished at: $(now)"
