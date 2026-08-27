#!/usr/bin/env bash
#
# gate-x bootstrap — check for Python 3.12, install it if missing, install the
# compiled gate-x wheel from the latest release, and verify it runs.
#
# Usage:
#   ./bootstrap.sh [--dir DIR] [--server URL] [--key GATEX-XXXX-...] [--yes]
#
#   --dir DIR      install location (default: ./gate-x)
#   --server URL   licence server, used for the optional activation check
#   --key KEY      licence key; with --server, the script activates and verifies
#   --yes          don't prompt before installing system packages (needs sudo)
#
# Safe to re-run. It never touches the system Python; it builds an isolated venv.
set -euo pipefail

REPO="SEKAI-MIRROR/gate-x-cli"
NEED_MAJOR=3
NEED_MINOR=12

DIR="gate-x"
SERVER=""
KEY=""
ASSUME_YES=0

# ---- pretty output -------------------------------------------------------
if [ -t 1 ]; then
  B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; C=$'\033[36m'; Z=$'\033[0m'
else
  B=""; G=""; Y=""; R=""; C=""; Z=""
fi
say()  { printf '%s==>%s %s\n' "$C" "$Z" "$*"; }
ok()   { printf '%s ok %s %s\n' "$G" "$Z" "$*"; }
warn() { printf '%s !! %s %s\n' "$Y" "$Z" "$*" >&2; }
die()  { printf '%serror%s %s\n' "$R" "$Z" "$*" >&2; exit 1; }

# ---- args ----------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --dir)    DIR="${2:?}"; shift 2 ;;
    --server) SERVER="${2:?}"; shift 2 ;;
    --key)    KEY="${2:?}"; shift 2 ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

# ---- find a suitable python ---------------------------------------------
is_ok_python() {
  # $1 = interpreter; true when it is exactly 3.12.x
  local v
  v="$("$1" -c 'import sys;print("%d.%d"%sys.version_info[:2])' 2>/dev/null)" || return 1
  [ "$v" = "${NEED_MAJOR}.${NEED_MINOR}" ]
}

find_python() {
  local candidate
  for candidate in python${NEED_MAJOR}.${NEED_MINOR} python3 python; do
    if command -v "$candidate" >/dev/null 2>&1 && is_ok_python "$candidate"; then
      command -v "$candidate"; return 0
    fi
  done
  # pyenv shim, if the user manages versions that way
  if command -v pyenv >/dev/null 2>&1; then
    local root; root="$(pyenv root 2>/dev/null || echo "$HOME/.pyenv")"
    for candidate in "$root"/versions/${NEED_MAJOR}.${NEED_MINOR}*/bin/python; do
      [ -x "$candidate" ] && is_ok_python "$candidate" && { echo "$candidate"; return 0; }
    done
  fi
  return 1
}

# ---- install python 3.12 -------------------------------------------------
confirm() {
  [ "$ASSUME_YES" = 1 ] && return 0
  printf '%s?%s %s [y/N] ' "$Y" "$Z" "$1"
  read -r reply; [ "$reply" = y ] || [ "$reply" = Y ]
}

sudo_run() {
  if [ "$(id -u)" = 0 ]; then "$@"; else sudo "$@"; fi
}

install_python() {
  local os; os="$(uname -s)"

  if [ "$os" = Darwin ]; then
    command -v brew >/dev/null || die "install Homebrew first: https://brew.sh"
    confirm "brew install python@${NEED_MAJOR}.${NEED_MINOR}?" || die "declined"
    brew install "python@${NEED_MAJOR}.${NEED_MINOR}"
    return
  fi

  [ "$os" = Linux ] || die "unsupported OS '$os'; install Python ${NEED_MAJOR}.${NEED_MINOR} manually"

  local id="unknown"
  [ -r /etc/os-release ] && id="$(. /etc/os-release; echo "${ID_LIKE:-$ID}")"

  case "$id" in
    *debian*|*ubuntu*)
      confirm "apt install python${NEED_MAJOR}.${NEED_MINOR} (may add the deadsnakes PPA)?" || die "declined"
      sudo_run apt-get update
      if ! sudo_run apt-get install -y "python${NEED_MAJOR}.${NEED_MINOR}" \
             "python${NEED_MAJOR}.${NEED_MINOR}-venv"; then
        say "python${NEED_MAJOR}.${NEED_MINOR} not in the base repo; adding deadsnakes"
        sudo_run apt-get install -y software-properties-common
        sudo_run add-apt-repository -y ppa:deadsnakes/ppa
        sudo_run apt-get update
        sudo_run apt-get install -y "python${NEED_MAJOR}.${NEED_MINOR}" \
               "python${NEED_MAJOR}.${NEED_MINOR}-venv"
      fi
      ;;
    *fedora*|*rhel*|*centos*)
      confirm "dnf install python${NEED_MAJOR}.${NEED_MINOR}?" || die "declined"
      sudo_run dnf install -y "python${NEED_MAJOR}.${NEED_MINOR}"
      ;;
    *suse*)
      confirm "zypper install python3${NEED_MINOR}?" || die "declined"
      sudo_run zypper install -y "python3${NEED_MINOR}"
      ;;
    *arch*)
      warn "Arch ships the latest Python, not necessarily ${NEED_MAJOR}.${NEED_MINOR}."
      warn "Use pyenv:  pyenv install ${NEED_MAJOR}.${NEED_MINOR}  then re-run this script."
      die "install python ${NEED_MAJOR}.${NEED_MINOR} via pyenv and retry"
      ;;
    *)
      die "unknown distro; install Python ${NEED_MAJOR}.${NEED_MINOR} yourself, then re-run"
      ;;
  esac
}

# ---- latest wheel url ----------------------------------------------------
latest_wheel_url() {
  local api="https://api.github.com/repos/$REPO/releases/latest"
  local auth=()
  [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
  curl -fsSL "${auth[@]}" "$api" \
    | grep -oE 'https://[^"]+\.whl' \
    | head -1
}

# ---- go ------------------------------------------------------------------
say "checking for Python ${NEED_MAJOR}.${NEED_MINOR}"
if PY="$(find_python)"; then
  ok "found $PY ($("$PY" -V 2>&1))"
else
  warn "Python ${NEED_MAJOR}.${NEED_MINOR} not found"
  install_python
  PY="$(find_python)" || die "installation finished but Python ${NEED_MAJOR}.${NEED_MINOR} is still not visible"
  ok "installed $PY ($("$PY" -V 2>&1))"
fi

say "creating virtualenv in $DIR/.venv"
mkdir -p "$DIR"
"$PY" -m venv "$DIR/.venv"
VENV="$DIR/.venv"
"$VENV/bin/python" -m pip install --quiet --upgrade pip
ok "venv ready"

say "resolving the latest gate-x wheel"
URL="$(latest_wheel_url)" || true
[ -n "$URL" ] || die "no wheel in the latest release of $REPO yet"
ok "$URL"

say "installing"
if ! "$VENV/bin/pip" install --quiet "$URL"; then
  die "pip install failed — is this Python ${NEED_MAJOR}.${NEED_MINOR} on a supported platform (Linux x86_64)?"
fi
ok "installed"

# ---- self-check ----------------------------------------------------------
say "verifying the install"
GATEX="$VENV/bin/gate-x"
[ -x "$GATEX" ] || die "gate-x entry point missing"

"$GATEX" version >/dev/null || die "gate-x failed to run"
ok "gate-x runs: $("$GATEX" version 2>/dev/null | tail -1)"

# plugin entry point must be discoverable, or licensing never engages
"$VENV/bin/python" - <<'PY' || die "licence plugin not discovered — activation would fail"
from importlib.metadata import entry_points
eps = [e.name for e in entry_points(group="gatex.plugins")]
assert "license" in eps, f"gatex.plugins missing 'license': {eps}"
import gatex_license
assert gatex_license.PLUGIN.id == "license"
print("plugin ok")
PY
ok "licence plugin discovered"

# ---- put `gate-x` on PATH ------------------------------------------------
# Symlinks the venv binary into a bin dir and, when that dir is not on PATH,
# appends one export line to ~/.bashrc / ~/.zshrc / ~/.profile. All of it lives
# in gatex.cli.units so `gate-x start` and `gate-x uninstall` share the logic.
say "putting gate-x on your PATH"
PATH_OUT="$("$VENV/bin/python" - <<'PY' || true
from gatex.cli import units
link, edited = units.ensure_path()
print(link or "")
print(", ".join(str(rc) for rc in edited))
PY
)"
LINK="$(printf '%s\n' "$PATH_OUT" | sed -n 1p)"
EDITED="$(printf '%s\n' "$PATH_OUT" | sed -n 2p)"
if [ -n "$LINK" ]; then
  ok "$LINK"
  [ -n "$EDITED" ] && ok "PATH line added to $EDITED"
else
  warn "could not create a gate-x shim; use $GATEX directly"
fi

# ---- optional live activation -------------------------------------------
if [ -n "$KEY" ] && [ -n "$SERVER" ]; then
  say "activating $KEY against $SERVER"
  if "$GATEX" license activate "$KEY" --server "$SERVER" --label "$(hostname)"; then
    ok "activation succeeded"
    "$GATEX" license status || true
  else
    die "activation failed — check the key, the server URL, and the device limit"
  fi
elif [ -n "$KEY$SERVER" ]; then
  warn "give BOTH --key and --server to run the activation check; skipping"
fi

# ---- done ----------------------------------------------------------------
printf '\n%s%s installed %s\n' "$B" "$G" "$Z"

# A script cannot reload the shell that launched it, so the command to run
# depends on whether THIS shell can already see the shim.
CMD="$GATEX"
RELOAD=""
if [ -n "$LINK" ] && [ "$(command -v gate-x 2>/dev/null)" = "$LINK" ]; then
  CMD="gate-x"
elif [ -n "$EDITED" ]; then
  CMD="gate-x"
  RELOAD="exec \$SHELL -l   # or just open a new terminal"
fi

cat <<DONE

One more step — run this and paste your licence key:

${RELOAD:+     $RELOAD
}     $CMD start

That activates the licence, configures everything, starts the service and its
auto-updater, and prints your panel URL. Nothing else to set up.

DONE
