#!/usr/bin/env bash
#
# gate-x install-service — run gate-x as a systemd --user service, plus a
# timer that checks for updates every 5 minutes and restarts the service when
# one is applied. Run this after bootstrap.sh / install.sh.
#
# Usage:
#   ./install-service.sh [--dir DIR] [--interval SECONDS]
#
#   --dir DIR           install location used by bootstrap.sh (default: gate-x)
#   --interval SECONDS  update-check interval (default: 300)
#
# Requires systemd --user (any normal Linux desktop/server has this). On a
# VPS you SSH into, user units stop when you log out unless lingering is on;
# this script enables it (needs sudo, asks once).
set -euo pipefail

DIR="gate-x"
INTERVAL=300

while [ $# -gt 0 ]; do
  case "$1" in
    --dir)      DIR="${2:?}"; shift 2 ;;
    --interval) INTERVAL="${2:?}"; shift 2 ;;
    -h|--help)  grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

ABS_DIR="$(cd "$DIR" 2>/dev/null && pwd)" || { echo "no install at '$DIR' — run bootstrap.sh first" >&2; exit 1; }
GATEX="$ABS_DIR/.venv/bin/gate-x"
[ -x "$GATEX" ] || { echo "$GATEX not found — run bootstrap.sh first" >&2; exit 1; }

UNIT_DIR="$HOME/.config/systemd/user"
mkdir -p "$UNIT_DIR"

[ -f "$ABS_DIR/config.yaml" ] || cat > "$ABS_DIR/config.yaml" <<CFG
host: 127.0.0.1
port: 8317
CFG

cat > "$UNIT_DIR/gatex.service" <<UNIT
[Unit]
Description=gate-x proxy
After=network-online.target
Wants=network-online.target

[Service]
Type=exec
WorkingDirectory=$ABS_DIR
ExecStart=$GATEX -c $ABS_DIR/config.yaml serve
Restart=on-failure
# 3s hot-looped an unlicensed box ~2,900 times a day; 30s still recovers from a
# transient license-server outage without burning a core on it.
RestartSec=30
# Exit 1 is the licence gate refusing to start: it needs an operator, not a
# retry. Exit 3 (uvicorn startup failure, e.g. the license server unreachable)
# can clear on its own, so that one keeps retrying.
RestartPreventExitStatus=1

[Install]
WantedBy=default.target
UNIT

cat > "$UNIT_DIR/gatex-update.service" <<UNIT
[Unit]
Description=gate-x self-update check

[Service]
Type=oneshot
ExecStart=$GATEX -c $ABS_DIR/config.yaml update --apply --yes
UNIT

cat > "$UNIT_DIR/gatex-update.timer" <<UNIT
[Unit]
Description=Check gate-x for updates

[Timer]
# OnActiveSec, not OnBootSec: this is relative to the timer starting, so it
# always has a first elapse in the future. OnBootSec on a box with weeks of
# uptime is already in the past, which leaves the timer "active (elapsed)"
# with Trigger: n/a — dead, and it never recovers on its own.
OnActiveSec=${INTERVAL}s
OnUnitActiveSec=${INTERVAL}s
AccuracySec=5s
Persistent=true

[Install]
WantedBy=timers.target
UNIT

systemctl --user daemon-reload
systemctl --user enable --now gatex.service
systemctl --user enable --now gatex-update.timer

if command -v loginctl >/dev/null 2>&1 && ! loginctl show-user "$USER" -p Linger 2>/dev/null | grep -q 'yes'; then
  echo "enabling linger so gate-x keeps running after you log out (needs sudo)"
  sudo loginctl enable-linger "$USER" || echo "!! could not enable linger; gate-x will stop when this SSH session ends" >&2
fi

echo "installed:"
echo "  gatex.service         — the proxy, restarts on crash"
echo "  gatex-update.timer    — checks for updates every ${INTERVAL}s, auto-applies and restarts the proxy"
echo
echo "check with: systemctl --user status gatex.service gatex-update.timer"
