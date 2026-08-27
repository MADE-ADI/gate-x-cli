#!/usr/bin/env bash
# Convenience installer: fetch the latest compiled wheel into a venv.
set -euo pipefail
REPO="SEKAI-MIRROR/gate-x-cli"
PY="${PYTHON:-python3.12}"
command -v "$PY" >/dev/null || { echo "need Python 3.12 ($PY not found)"; exit 1; }

DIR="${1:-gate-x}"
"$PY" -m venv "$DIR/.venv"
URL="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
  | grep -oE 'https://[^"]+\.whl' | head -1)"
[ -n "$URL" ] || { echo "no wheel in the latest release yet"; exit 1; }
"$DIR/.venv/bin/pip" install --upgrade pip >/dev/null
"$DIR/.venv/bin/pip" install "$URL"
echo "installed into $DIR/.venv — run: $DIR/.venv/bin/gate-x --help"
