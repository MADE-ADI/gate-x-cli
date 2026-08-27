#!/usr/bin/env bash
#
# gate-x manual update — install the latest release over an existing install,
# keeping credentials (~/.gate-x) and config.yaml untouched.
#
# Usage:
#   ./update.sh [--dir DIR] [--repo owner/name] [--no-backup]
#
#   --dir DIR      install location (default: ./gate-x, then ~/gate-x)
#   --repo O/N     release repo override (default: SEKAI-MIRROR/gate-x-cli)
#   --no-backup    skip the config/credential tarball taken before installing
#
# Safe to re-run. Only the Python package is replaced; the service is restarted
# when it is running under systemd.
set -euo pipefail

REPO="${GATEX_UPDATE_REPO:-SEKAI-MIRROR/gate-x-cli}"
DIR=""
BACKUP=1

if [ -t 1 ]; then
  G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; C=$'\033[36m'; Z=$'\033[0m'
else
  G=""; Y=""; R=""; C=""; Z=""
fi
say()  { printf '%s==>%s %s\n' "$C" "$Z" "$*"; }
ok()   { printf '%s ok %s %s\n' "$G" "$Z" "$*"; }
warn() { printf '%s !! %s %s\n' "$Y" "$Z" "$*" >&2; }
die()  { printf '%serror%s %s\n' "$R" "$Z" "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --dir)  DIR="${2:?}"; shift 2 ;;
    --repo) REPO="${2:?}"; shift 2 ;;
    --no-backup) BACKUP=0; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

# ---- locate the install --------------------------------------------------
find_venv() {
  local candidate
  for candidate in ${DIR:+"$DIR"} "gate-x" "$HOME/gate-x"; do
    if [ -x "$candidate/.venv/bin/gate-x" ]; then echo "$candidate/.venv"; return 0; fi
  done
  # installed elsewhere but on PATH: resolve the shim back to its venv
  if command -v gate-x >/dev/null 2>&1; then
    candidate="$(readlink -f "$(command -v gate-x)")"
    if [ -x "$candidate" ]; then dirname "$(dirname "$candidate")"; return 0; fi
  fi
  return 1
}

VENV="$(find_venv)" || die "no gate-x install found; pass --dir, or run bootstrap.sh first"
GATEX="$VENV/bin/gate-x"
ok "install: $VENV ($("$GATEX" version 2>/dev/null | tail -1))"

# ---- back up the state an update must never touch ------------------------
AUTH_DIR="$HOME/.gate-x"
[ -d "$AUTH_DIR" ] || AUTH_DIR="$HOME/.cli-proxy-api"
if [ "$BACKUP" = 1 ] && [ -d "$AUTH_DIR" ]; then
  ARCHIVE="$HOME/gate-x-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
  ARGS=(-C "$HOME" "$(basename "$AUTH_DIR")")
  CONFIG="$(dirname "$VENV")/config.yaml"
  if [ -f "$CONFIG" ]; then ARGS+=(-C "$(dirname "$CONFIG")" config.yaml); fi
  tar -czf "$ARCHIVE" "${ARGS[@]}"
  ok "backup: $ARCHIVE"
fi

# ---- update --------------------------------------------------------------
# Anything from v0.1.1 knows how to update itself, including rewriting systemd
# units (a wheel cannot carry those) and restarting the service.
if "$GATEX" update --help >/dev/null 2>&1; then
  say "running gate-x update --apply"
  GATEX_UPDATE_REPO="$REPO" "$GATEX" update --apply --yes
  exit 0
fi

warn "this build predates 'gate-x update'; installing the latest wheel by hand"
API="https://api.github.com/repos/$REPO/releases/latest"
AUTH=()
if [ -n "${GITHUB_TOKEN:-}" ]; then AUTH=(-H "Authorization: Bearer $GITHUB_TOKEN"); fi
TAG="$(curl -fsSL "${AUTH[@]}" "$API" | grep -oE '"tag_name": *"[^"]+"' | head -1 | cut -d'"' -f4)"
ABI="cp$("$VENV/bin/python" -c 'import sys;print("%d%d"%sys.version_info[:2])')"
URL="$(curl -fsSL "${AUTH[@]}" "$API" | grep -oE 'https://[^"]+\.whl' | grep -- "$ABI" | head -1)"
[ -n "$URL" ] || URL="$(curl -fsSL "${AUTH[@]}" "$API" | grep -oE 'https://[^"]+\.whl' | head -1)"
[ -n "$URL" ] || die "no wheel in the latest release of $REPO"

say "installing ${TAG:-latest}: $(basename "$URL")"
"$VENV/bin/pip" install --quiet --upgrade --force-reinstall "$URL" || die "pip install failed"
ok "installed: $("$GATEX" version 2>/dev/null | tail -1)"

# Now that a newer gate-x is in place, let it fix the units and restart itself.
"$GATEX" update --apply --yes >/dev/null 2>&1 || true

for SCOPE in --user --system; do
  if systemctl $SCOPE is-active gatex.service >/dev/null 2>&1; then
    systemctl $SCOPE restart gatex.service && ok "restarted gatex.service ($SCOPE)"
    exit 0
  fi
done
warn "gate-x is not running under systemd; restart it yourself"
