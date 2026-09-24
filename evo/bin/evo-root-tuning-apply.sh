#!/usr/bin/env bash
# EVO Strix Halo host tuning (memlock + IOMMU off + GTT/TTM).
# Run: sudo bash ~/bin/evo-root-tuning-apply.sh
# Does NOT reboot — reboot yourself after reviewing the summary.
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "ERROR: must run as root (sudo bash $0)" >&2
  exit 1
fi

PARAMS="amdgpu.vm_update_mode=0 amdgpu.noretry=0 amdgpu.gttsize=126976 ttm.pages_limit=32505856 amdgpu.sg_display=0 amd_iommu=off"
TS="$(date +%Y%m%d%H%M%S)"
BACKUP_DIR="/root/evo-root-tuning-backups-${TS}"
mkdir -p "$BACKUP_DIR"
LOG="$HOME/logs/evo-root-tuning-apply-${TS}.log"
mkdir -p $HOME/logs
touch "$LOG"
chown user:user "$LOG" 2>/dev/null || true

log() { echo "$*" | tee -a "$LOG"; }

backup() {
  local f="$1"
  if [[ -e "$f" ]]; then
    local dest="$BACKUP_DIR/$(echo "$f" | sed 's|^/||; s|/|__|g').bak"
    cp -a "$f" "$dest"
    log "backup: $f -> $dest"
  else
    log "backup: $f (missing — will create new)"
    : > "$BACKUP_DIR/$(echo "$f" | sed 's|^/||; s|/|__|g').WAS_MISSING"
  fi
}

log "=== EVO root tuning apply @ $(date -Is) ==="
log "backup dir: $BACKUP_DIR"

# --- memlock: limits.d ---
LIM=/etc/security/limits.d/99-memlock.conf
backup "$LIM"
cat > "$LIM" << 'EOF'
# EVO Strix Halo — unlimited memlock for weight pin (halogen-style PIN_TRUNK)
# Applied by evo-root-tuning-apply.sh
* soft memlock unlimited
* hard memlock unlimited
user soft memlock unlimited
user hard memlock unlimited
EOF
log "wrote $LIM"

# --- memlock: systemd drop-ins ---
SYS_D=/etc/systemd/system.conf.d
USR_D=/etc/systemd/user.conf.d
mkdir -p "$SYS_D" "$USR_D"
SYS_F="$SYS_D/99-memlock.conf"
USR_F="$USR_D/99-memlock.conf"
backup "$SYS_F"
backup "$USR_F"
cat > "$SYS_F" << 'EOF'
[Manager]
DefaultLimitMEMLOCK=infinity
EOF
cp -a "$SYS_F" "$USR_F"
log "wrote $SYS_F and $USR_F"

# --- kernel cmdline (detect mechanism) ---
MECH=""
if [[ -f /etc/default/grub ]] && command -v update-grub >/dev/null 2>&1; then
  MECH="grub"
elif [[ -f /etc/kernel/cmdline ]]; then
  MECH="kernel-cmdline"
elif command -v kernelstub >/dev/null 2>&1; then
  MECH="kernelstub"
else
  log "ERROR: could not detect boot config mechanism"
  exit 1
fi
log "boot mechanism: $MECH"

append_params_idempotent() {
  # stdin: current cmdline string; stdout: updated
  local cur="$1"
  local out="$cur"
  local p
  for p in amdgpu.vm_update_mode=0 amdgpu.noretry=0 amdgpu.gttsize=126976 ttm.pages_limit=32505856 amdgpu.sg_display=0 amd_iommu=off; do
    local key="${p%%=*}"
    # strip existing key=... token(s)
    out="$(echo "$out" | sed -E "s/(^| )${key}=[^ ]*//g; s/  +/ /g; s/^ //; s/ $//")"
  done
  if [[ -n "$out" ]]; then
    echo "$out $PARAMS"
  else
    echo "$PARAMS"
  fi
}

case "$MECH" in
  grub)
    GRUB=/etc/default/grub
    backup "$GRUB"
    backup /boot/grub/grub.cfg
    # Prefer GRUB_CMDLINE_LINUX for these hardware params; keep DEFAULT intact.
    if ! grep -q '^GRUB_CMDLINE_LINUX=' "$GRUB"; then
      echo 'GRUB_CMDLINE_LINUX=""' >> "$GRUB"
    fi
    cur="$(grep '^GRUB_CMDLINE_LINUX=' "$GRUB" | head -1 | sed -E 's/^GRUB_CMDLINE_LINUX="//; s/"$//')"
    new="$(append_params_idempotent "$cur")"
    # rewrite line safely
    tmp="$(mktemp)"
    awk -v n="$new" '
      BEGIN { done=0 }
      /^GRUB_CMDLINE_LINUX=/ && !done {
        print "GRUB_CMDLINE_LINUX=\"" n "\""
        done=1
        next
      }
      { print }
      END { if (!done) print "GRUB_CMDLINE_LINUX=\"" n "\"" }
    ' "$GRUB" > "$tmp"
    mv "$tmp" "$GRUB"
    log "GRUB_CMDLINE_LINUX=\"$new\""
    log "running update-grub..."
    update-grub
    log "update-grub OK"
    log "verify snippets from grub.cfg:"
    grep -E 'amd_iommu|gttsize|ttm.pages_limit' /boot/grub/grub.cfg | head -10 | tee -a "$LOG" || true
    ;;
  kernel-cmdline)
    CMD=/etc/kernel/cmdline
    backup "$CMD"
    cur="$(tr '\n' ' ' < "$CMD" | sed 's/  */ /g; s/^ //; s/ $//')"
    new="$(append_params_idempotent "$cur")"
    printf '%s\n' "$new" > "$CMD"
    log "wrote $CMD: $new"
    if command -v kernel-install >/dev/null 2>&1; then
      KVER="$(uname -r)"
      log "kernel-install add $KVER ..."
      kernel-install add "$KVER" "/boot/vmlinuz-$KVER" "/boot/initrd.img-$KVER" || \
        kernel-install add "$KVER" "/boot/vmlinuz-$KVER" || true
    fi
    ;;
  kernelstub)
    backup /etc/kernelstub/configuration 2>/dev/null || true
    # remove then add for idempotency
    for p in amdgpu.vm_update_mode=0 amdgpu.noretry=0 amdgpu.gttsize=126976 ttm.pages_limit=32505856 amdgpu.sg_display=0 amd_iommu=off; do
      key="${p%%=*}"
      kernelstub -d -p "$key" 2>/dev/null || true
    done
    kernelstub -a "amd_iommu=off"
    kernelstub -a "amdgpu.gttsize=126976"
    kernelstub -a "ttm.pages_limit=32505856"
    log "kernelstub params added"
    ;;
esac

log ""
log "========== SUMMARY =========="
log "Backups:     $BACKUP_DIR"
log "Memlock:     $LIM + systemd DefaultLimitMEMLOCK=infinity"
log "Kernel:      $PARAMS  (via $MECH)"
log "Log:         $LOG"
log ""
log "NOT rebooting. When ready:"
log "  sudo reboot"
log ""
log "After reboot, verify:"
log "  cat /proc/cmdline          # expect amd_iommu=off gttsize=126976 ttm.pages_limit=32505856"
log "  ulimit -l                  # expect unlimited"
log "  cat /sys/class/drm/card*/device/mem_info_gtt_total"
log "  ls /sys/class/iommu        # expect empty / no ivhd if IOMMU off"
log ""
log "Revert:"
log "  sudo bash $HOME/bin/evo-root-tuning-revert.sh $BACKUP_DIR"
log "=============================="
