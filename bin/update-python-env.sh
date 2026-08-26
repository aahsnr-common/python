#!/usr/bin/env bash
# bin/update-python-env.sh
#
# Updates uv itself, the pinned Python 3.14 interpreter, and every
# library/tool listed in requirements.txt — then removes what's left
# over from the previous versions (superseded Python patch builds,
# packages no longer in requirements.txt, stale uv cache entries).
#
# Runs automatically from .envrc on a schedule (default: weekly).
# You can also just run it by hand any time:
#
#   ./bin/update-python-env.sh
#
# Env vars:
#   UV_ENVRC_PURGE_OTHER_MINORS=1   also uninstall every uv-managed
#                                   Python minor version OTHER than the
#                                   one this project pins. Off by
#                                   default because other projects on
#                                   the same machine may pin a
#                                   different version.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

PY_VERSION_FILE="$PROJECT_ROOT/.python-version"
REQ_FILE="$PROJECT_ROOT/requirements.txt"
VENV_DIR="$PROJECT_ROOT/.venv"
VENV_PY="$VENV_DIR/bin/python"
PURGE_OTHER_MINORS="${UV_ENVRC_PURGE_OTHER_MINORS:-0}"

PY_VERSION="3.14"
if [ -f "$PY_VERSION_FILE" ]; then
  PY_VERSION="$(tr -d '[:space:]' < "$PY_VERSION_FILE")"
fi

log() { printf '[update-python-env] %s\n' "$*"; }

command -v uv >/dev/null 2>&1 || { echo "uv is not installed or not on PATH" >&2; exit 1; }

log "starting maintenance run: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
log "uv version: $(uv --version)"

# -----------------------------------------------------------------
# 1. Update uv itself.
#    Silently skipped (not a fatal error) if uv was installed via a
#    package manager like Homebrew/apt, which manage their own updates.
# -----------------------------------------------------------------
log "checking for a newer uv release"
if ! uv self update; then
  log "uv self update skipped (likely installed via an external package manager)"
fi

# -----------------------------------------------------------------
# 2. Make sure Python $PY_VERSION is installed, then upgrade it to its
#    latest patch release. Stable since uv 0.10 (uv python upgrade /
#    uv python install --upgrade); existing venvs created against the
#    minor-version pin pick up the new patch transparently.
# -----------------------------------------------------------------
log "ensuring Python ${PY_VERSION} is installed"
uv python install "$PY_VERSION"

log "upgrading Python ${PY_VERSION} to its latest patch release"
uv python upgrade "$PY_VERSION"

if [ ! -x "$VENV_PY" ]; then
  log "no .venv found — creating one against Python ${PY_VERSION}"
  uv venv --python "$PY_VERSION" "$VENV_DIR"
fi

# -----------------------------------------------------------------
# 3. Upgrade every package in requirements.txt to the newest version
#    its specifier allows, then prune anything installed that is no
#    longer listed there. (uv pip install never removes packages on
#    its own — uv pip sync is what enforces "venv == requirements.txt".)
# -----------------------------------------------------------------
if [ -f "$REQ_FILE" ]; then
  log "upgrading libraries/tools from requirements.txt"
  uv pip install --upgrade -r "$REQ_FILE" --python "$VENV_PY"

  log "removing packages no longer listed in requirements.txt"
  uv pip sync "$REQ_FILE" --python "$VENV_PY"
else
  log "no requirements.txt found — skipping library upgrade"
fi

# -----------------------------------------------------------------
# 4. Upgrade any CLI tools installed globally with `uv tool install`.
# -----------------------------------------------------------------
if [ -n "$(uv tool list 2>/dev/null || true)" ]; then
  log "upgrading uv-managed CLI tools"
  uv tool upgrade --all
fi

# -----------------------------------------------------------------
# 5. Remove superseded patch releases of the pinned Python minor
#    version, e.g. delete 3.14.1 once 3.14.2 is installed.
# -----------------------------------------------------------------
log "checking for superseded Python ${PY_VERSION} patch releases"
installed_patches="$(uv python list --only-installed 2>/dev/null \
  | grep -o "cpython-${PY_VERSION//./\\.}\.[0-9]*" | sort -u || true)"

if [ -n "$installed_patches" ]; then
  current_patch="$(echo "$installed_patches" | sort -V | tail -n1)"
  echo "$installed_patches" | grep -v "^${current_patch}$" | while read -r old; do
    ver="${old#cpython-}"
    log "uninstalling superseded Python ${ver}"
    uv python uninstall "$ver" || true
  done
fi

# -----------------------------------------------------------------
# Optional (opt-in): remove every OTHER Python minor version uv
# manages on this machine. Leave this off if the machine hosts other
# projects pinned to a different Python version.
# -----------------------------------------------------------------
if [ "$PURGE_OTHER_MINORS" = "1" ]; then
  log "purging Python minor versions other than ${PY_VERSION} (opt-in cleanup)"
  uv python list --only-installed 2>/dev/null \
    | grep -o 'cpython-[0-9]*\.[0-9]*\.[0-9]*' | sort -u \
    | grep -v "^cpython-${PY_VERSION//./\\.}\." | while read -r old; do
        ver="${old#cpython-}"
        log "uninstalling unrelated Python ${ver}"
        uv python uninstall "$ver" || true
      done
fi

# -----------------------------------------------------------------
# 6. Reclaim disk space from stale cache entries. `uv cache prune`
#    only removes entries nothing references (unlike `uv cache clean`,
#    which wipes the whole cache and would slow down the next install).
# -----------------------------------------------------------------
log "pruning the uv cache"
uv cache prune

log "maintenance run complete: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
