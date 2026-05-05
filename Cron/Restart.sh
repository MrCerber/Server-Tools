#!/bin/bash

# ================= CONFIG =================
REBOOT_DELAY_MIN=5
REASON_DEFAULT="Automatic reboot required after system updates"
LOG_PREFIX="[AUTO-REBOOT]"
HISTORY_FILE="/var/log/reboot-history.log"
MOTD_FILE="/etc/motd"
REBOOT_FLAG="/var/run/reboot-required"
REASON_FILE="/var/run/reboot-required.pkgs"
# ==========================================

now() {
  date '+%Y-%m-%d %H:%M:%S'
}

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
cat > "$MOTD_FILE" <<EOF
Last system reboot was scheduled automatically.
Time: $REBOOT_TIME
Reason: $REASON
EOF

# ---- Append reboot history ----
echo "$(now) | Scheduled reboot at $REBOOT_TIME | Reason: $REASON" >> "$HISTORY_FILE"

# ---- Schedule reboot (systemd managed) ----
shutdown -r "+$REBOOT_DELAY_MIN" "$REASON"

echo "$LOG_PREFIX Shutdown command issued"
echo "$LOG_PREFIX Cron finished at: $(now)"
