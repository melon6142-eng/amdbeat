#!/usr/bin/env bash
# Wrapper: prefer Virtual-* if present; else fall back to evo-x3 helper.
# Never fail hard — must not block graphical session / RustDesk.
set +e
export DISPLAY="${DISPLAY:-:0}"
if [[ -z "${XAUTHORITY:-}" ]]; then
  for a in /run/user/"${UID}"/gdm/Xauthority "$HOME/.Xauthority"; do
    [[ -f "$a" ]] && export XAUTHORITY="$a" && break
  done
fi
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/${UID}}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"
gnome-extensions disable ding@rastersoft.com 2>/dev/null || true
OUT=""
for name in Virtual Virtual-1 Virtual-2; do
  if xrandr --query 2>/dev/null | grep -q "^${name} connected"; then
    OUT=$name
    break
  fi
done
if [[ -n "$OUT" ]]; then
  xrandr --output "$OUT" --mode 1920x1080 --primary 2>/dev/null || xrandr --output "$OUT" --auto --primary
  xset s off 2>/dev/null || true
  xset -dpms 2>/dev/null || true
  xrandr --listactivemonitors
  exit 0
fi
# No Virtual connector: use resilient evo-x3 helper (real HDMI/DP/etc.)
if [[ -x /usr/local/bin/evo-x3-virtual-monitor.sh ]]; then
  exec /usr/local/bin/evo-x3-virtual-monitor.sh
fi
echo "No Virtual output; evo-x3 helper missing — continuing without virtual monitor" >&2
exit 0
