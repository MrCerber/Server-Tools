# Server Tools — CLAUDE.md

## Project overview

A personal bash bootstrap toolkit for fresh Ubuntu/Debian servers.
Run as root via SSH. No user creation, no timezone changes, no swap changes.

## Files

| File | Purpose |
|---|---|
| `install.sh` | Main interactive menu script (~500 lines) |
| `99-mrcerber` | Custom MOTD script — installed to `/etc/update-motd.d/99-mrcerber` |
| `logo.txt` | ASCII art logo — installed to `/etc/update-motd.d/logo.txt` |

## Key conventions

- `set -Eeuo pipefail` at the top — strict error handling, always keep it
- Every destructive action calls `backup_file` or `backup_dir_tar` first
- Every significant action calls `log_action` — log goes to `/root/.mrcerber-bootstrap.log`
- Internet-dependent functions call `require_internet_or_warn` before downloading
- `confirm()` is required before any irreversible/destructive operation (e.g. UFW reset)
- `DEBIAN_FRONTEND=noninteractive` on all `apt-get install` calls

## Menu structure

```
Main menu
├── System       (1-4)  update, packages, auto-updates
├── MOTD & SSH   (5-7)  custom MOTD, restore, preview
├── Security     (8-9)  UFW submenu, Fail2ban submenu
└── Extras      (10-11) aliases, show log
```

## UI helpers (defined in install.sh)

| Function | Usage |
|---|---|
| `_menu_header "Title"` | Print colored section header |
| `_menu_item "N" "Label" "desc"` | Print one menu row |
| `_menu_section "Name"` | Print a section label inside a menu |
| `_menu_footer` | Print closing separator |
| `_status_badge svc\|cmd name` | Print colored active/inactive/not-found badge |
| `_sep` | Print a `---` separator line |

## Runtime globals

| Variable | Default | Purpose |
|---|---|---|
| `BACKUP_DIR` | `/root/.mrcerber-bootstrap-backups` | All backups land here |
| `LOG_FILE` | `/root/.mrcerber-bootstrap.log` | Action log |
| `ALIASES_BASHRC` | `/root/.bashrc` | Where aliases are written |
| `MOTD_BASE_URL` | GitHub raw URL | Fallback download source for MOTD files |

## What NOT to do

- Do not add Oh My Posh — it was intentionally removed
- Do not skip `backup_file` / `backup_dir_tar` before modifying system files
- Do not remove `log_action` calls from existing functions
- Do not add `sudo` — script requires and checks for root via `require_root`
- Do not create swap, users, or timezone logic — out of scope by design
