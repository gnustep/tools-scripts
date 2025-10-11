#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE' >&2
Usage: run-for-os.sh <install|setup|build|post-install|script-name> [target]

Examples:
  ./run-for-os.sh install            # auto-detect OS and run install-dependencies-<os>
  ./run-for-os.sh build mingw64_nt   # run build-mingw64_nt
  ./run-for-os.sh windows-package mingw64_nt  # run arbitrary script name for target
USAGE
}

if [ $# -lt 1 ]; then
  usage
  exit 2
fi

ACTION="$1"
TARGET="${2-}"

# detect target if omitted
if [ -z "$TARGET" ]; then
  UNAME=$(uname -s 2>/dev/null || echo Unknown)
  case "$UNAME" in
    MINGW64*|MSYS_NT*|MINGW32*|MSYS*) TARGET=mingw64_nt ;;
    Darwin) TARGET=darwin ;;
    Linux) TARGET=linux ;;
    FreeBSD) TARGET=freebsd ;;
    OpenBSD) TARGET=openbsd ;;
    NetBSD) TARGET=netbsd ;;
    Haiku) TARGET=haiku ;;
    *) TARGET=linux ;;
  esac
fi

case "$ACTION" in
  install) SCRIPT="install-dependencies-$TARGET" ;;
  setup) SCRIPT="setup-$TARGET" ;;
  build) SCRIPT="build-$TARGET" ;;
  post-install) SCRIPT="post-install-$TARGET" ;;
  *) SCRIPT="$ACTION" ;; # allow arbitrary script name
esac

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
WRAPPER="$REPO_ROOT/os-scripts/$TARGET/$SCRIPT"

if [ -f "$WRAPPER" ]; then
  exec bash "$WRAPPER" "${@:3}"
elif [ -f "$REPO_ROOT/$SCRIPT" ]; then
  exec bash "$REPO_ROOT/$SCRIPT" "${@:3}"
else
  echo "Error: script '$SCRIPT' not found for target '$TARGET'." >&2
  exit 3
fi
