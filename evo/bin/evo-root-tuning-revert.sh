#!/usr/bin/env bash
# Revert EVO root tuning from a backup dir created by evo-root-tuning-apply.sh
# Run: sudo bash ~/bin/evo-root-tuning-revert.sh /root/evo-root-tuning-backups-TIMESTAMP
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "ERROR: must run as root (sudo bash $0 <backup-dir>)" >&2
  exit 1
fi

BACKUP_DIR="${1:-}"
if [[ -z "$BACKUP_DIR" || ! -d "$BACKUP_DIR" ]]; then
  echo "Usage: sudo bash $0 /root/evo-root-tuning-backups-TIMESTAMP" >&2
  echo "Available:" >&2
  ls -d /root/evo-root-tuning-backups-* 2>/dev/null || echo "  (none found)" >&2
  exit 1
fi

restore() {
  local live="$1"
  local bak="$BACKUP_DIR/$(echo "$live" | sed 's|^/||; s|/|__|g').bak"
  local missing="$BACKUP_DIR/$(echo "$live" | sed 's|^/||; s|/|__|g').WAS_MISSING"
  if [[ -f "$bak" ]]; then
    cp -a "$bak" "$live"
    echo "restored $live from $bak"
  elif [[ -f "$missing" ]]; then
    rm -f "$live"
    echo "removed $live (was missing before apply)"
  else
    echo "skip $live (no backup marker)"
  fi
}

echo "=== reverting from $BACKUP_DIR ==="
restore /etc/default/grub
restore /etc/security/limits.d/99-memlock.conf
restore /etc/systemd/system.conf.d/99-memlock.conf
restore /etc/systemd/user.conf.d/99-memlock.conf
restore /etc/kernel/cmdline

if [[ -f /etc/default/grub ]] && command -v update-grub >/dev/null 2>&1; then
  echo "running update-grub..."
  update-grub
fi

if [[ -f /etc/kernel/cmdline ]] && command -v kernel-install >/dev/null 2>&1; then
  KVER="$(uname -r)"
  kernel-install add "$KVER" "/boot/vmlinuz-$KVER" "/boot/initrd.img-$KVER" 2>/dev/null || true
fi

echo ""
echo "Revert done. Reboot to apply: sudo reboot"
echo "Note: if you used kernelstub originally, re-check kernelstub -p list manually."
