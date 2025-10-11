#!/usr/bin/env bash
set -euo pipefail
# detect-os.sh - determine canonical build target for this machine
# Prints one of: mingw64_nt mingw32_nt msys_nt darwin linux freebsd openbsd netbsd haiku

canonical_from_uname() {
  local u="$1"
  case "$u" in
    MINGW64*|MINGW32*|MSYS_NT*|MSYS*)
      # Prefer MSYSTEM if available
      if [ -n "${MSYSTEM:-}" ]; then
        case "$MSYSTEM" in
          MINGW64*) echo mingw64_nt; return 0;;
          MINGW32*) echo mingw32_nt; return 0;;
          MSYS*)   echo msys_nt; return 0;;
        esac
      fi
      # Fallback on uname pattern
      case "$u" in
        MINGW64*|MSYS_NT*|MINGW*) echo mingw64_nt ;; # common on Git for Windows
        MINGW32*) echo mingw32_nt ;;
        MSYS*) echo msys_nt ;;
        *) echo mingw64_nt ;;
      esac
      ;;
    CYGWIN*)
      # Cygwin often needs mingw-style tools; map to mingw32_nt as conservative default
      echo mingw32_nt
      ;;
    Darwin)
      echo darwin
      ;;
    FreeBSD)
      echo freebsd
      ;;
    OpenBSD)
      echo openbsd
      ;;
    NetBSD)
      echo netbsd
      ;;
    Haiku)
      echo haiku
      ;;
    Linux)
      # Detect WSL/WSL2
      if [ -f /proc/version ]; then
        if grep -qi microsoft /proc/version 2>/dev/null || grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
          # Treat WSL as linux (use linux toolchain)
          echo linux
          return 0
        fi
      fi
      # For ordinary Linux
      echo linux
      ;;
    *)
      echo linux
      ;;
  esac
}

# 1) If MSYSTEM explicitly set and looks like MINGW64/MINGW32/MSYS, prefer that
if [ -n "${MSYSTEM:-}" ]; then
  case "${MSYSTEM}" in
    MINGW64*) echo mingw64_nt; exit 0;;
    MINGW32*) echo mingw32_nt; exit 0;;
    MSYS*)   echo msys_nt; exit 0;;
  esac
fi

# 2) If on macOS use sw_vers as a hint
if command -v sw_vers >/dev/null 2>&1; then
  if [ "$(sw_vers -productName 2>/dev/null || true)" = "Mac OS X" ] || [ "$(sw_vers -productName 2>/dev/null || true)" = "macOS" ]; then
    echo darwin
    exit 0
  fi
fi

# 3) Try uname -s as a fallback
UNAME_S="$(uname -s 2>/dev/null || echo Unknown)"
canonical_from_uname "$UNAME_S"
