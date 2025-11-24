#!/usr/bin/env bash
# Ultra Sequoia rollback — restores from latest backup folder created by installer
set -euo pipefail

LATEST_BACKUP="$(ls -1dt /usr/share/sequoia_backup_* 2>/dev/null | head -n1 || true)"

if [ -z "$LATEST_BACKUP" ]; then
  echo "[ERR] No sequoia backup found under /usr/share/sequoia_backup_*"
  exit 1
fi

echo "[INFO] Restoring from backup: $LATEST_BACKUP"

# Restore common files we touched
restore() {
  local src="$1"
  local dest="$2"
  if [ -e "$LATEST_BACKUP$src" ]; then
    echo "[RESTORE] $dest from $LATEST_BACKUP$src"
    sudo cp -a "$LATEST_BACKUP$src" "$dest"
  else
    echo "[SKIP] No backup for $dest at $LATEST_BACKUP$src"
  fi
}

# Files (paths anchored under /usr)
restore "/usr/share/gnome-shell/theme/gnome-shell.css" "/usr/share/gnome-shell/theme/gnome-shell.css"
restore "/usr/share/nautilus/ui/nautilus.css" "/usr/share/nautilus/ui/nautilus.css"
restore "/usr/share/gnome-control-center/gnome-control-center.gresource" "/usr/share/gnome-control-center/gnome-control-center.gresource"
restore "/usr/share/gnome-shell/theme/gdm.css" "/usr/share/gnome-shell/theme/gdm.css"

echo "[INFO] Optional: you may need to restart gdm3 to apply changes (this will end your session)"
read -p "Restart gdm3 now? (y/N): " ans
if [[ "$ans" == "y" || "$ans" == "Y" ]]; then
  sudo systemctl restart gdm3 || echo "[WARN] failed to restart gdm3, please reboot manually"
fi

echo "[OK] Rollback finished. Reboot recommended."
