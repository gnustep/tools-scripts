#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# GNUstep clean build for macOS using X11
#
# Builds and installs:
#   - tools-make
#   - libs-base
#   - libs-gui
#   - libs-back
#
# Notes:
#   * XQuartz provides the X11 server/runtime on macOS.
#   * Homebrew provides the X11 development libraries/pkg-config files.
#   * This installs into /opt/GNUstep by default.
###############################################################################

PREFIX="${PREFIX:-/opt/GNUstep}"
SRCROOT="${SRCROOT:-$HOME/src/gnustep-core}"
JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}"

# Latest stable tags as of the cited upstream release pages.
TOOLS_MAKE_TAG="${TOOLS_MAKE_TAG:-make-2_9_3}"
LIBS_BASE_TAG="${LIBS_BASE_TAG:-base-1_31_1}"
LIBS_GUI_TAG="${LIBS_GUI_TAG:-gui-0_32_0}"
LIBS_BACK_TAG="${LIBS_BACK_TAG:-back-0_32_0}"

# Pick Homebrew prefix automatically.
if [[ -x /opt/homebrew/bin/brew ]]; then
  BREW=/opt/homebrew/bin/brew
elif [[ -x /usr/local/bin/brew ]]; then
  BREW=/usr/local/bin/brew
else
  echo "Homebrew not found. Install Homebrew first."
  exit 1
fi

BREW_PREFIX="$("$BREW" --prefix)"

# XQuartz paths.
X11_PREFIX="/opt/X11"

echo "==> Checking prerequisites"

if ! xcode-select -p >/dev/null 2>&1; then
  echo "Xcode Command Line Tools are not installed."
  echo "Run: xcode-select --install"
  exit 1
fi

if [[ ! -d "$X11_PREFIX" ]]; then
  echo "XQuartz is not installed at $X11_PREFIX."
  echo "Install it first:"
  echo "  brew install --cask xquartz"
  echo "or download from https://www.xquartz.org/"
  exit 1
fi

echo "==> Installing Homebrew dependencies"

"$BREW" install \
  autoconf automake libtool pkgconf gsed gawk coreutils \
  gcc make \
  libffi openssl@3 libxml2 libxslt icu4c zlib bdw-gc gnutls \
  jpeg-turbo libpng libtiff cairo fontconfig freetype \
  libx11 libxext libxt libxmu libxft libxrender libxfixes libxcursor libxrandr \
  libxi libxinerama libxcomposite libxdamage libxpm libicns portaudio

mkdir -p "$SRCROOT"
cd "$SRCROOT"

clone_or_update() {
  local repo="$1"
  local dir="$2"
  local tag="$3"

  if [[ ! -d "$dir/.git" ]]; then
    git clone "https://github.com/gnustep/${repo}.git" "$dir"
  fi

  git -C "$dir" fetch --tags --force
  git -C "$dir" checkout "$tag"
}

echo "==> Fetching sources"
clone_or_update tools-make tools-make "$TOOLS_MAKE_TAG"
clone_or_update libs-base  libs-base  "$LIBS_BASE_TAG"
clone_or_update libs-gui   libs-gui   "$LIBS_GUI_TAG"
clone_or_update libs-back  libs-back  "$LIBS_BACK_TAG"

# Common compiler and linker environment: GCC + legacy Apple Objective-C runtime only.
GCC_CC="$(ls -1 "$BREW_PREFIX"/bin/gcc-[0-9]* 2>/dev/null | sort -V | tail -n1)"
GCC_CXX="$(ls -1 "$BREW_PREFIX"/bin/g++-[0-9]* 2>/dev/null | sort -V | tail -n1)"

if [[ -z "$GCC_CC" || -z "$GCC_CXX" ]]; then
  echo "Homebrew GCC not found under $BREW_PREFIX/bin"
  echo "Try: $BREW install gcc"
  exit 1
fi

export PATH="$BREW_PREFIX/opt/icu4c/bin:$BREW_PREFIX/opt/libxml2/bin:$PATH"
export CC="$GCC_CC"
export CXX="$GCC_CXX"
export OBJC="$GCC_CC"
export OBJCXX="$GCC_CXX"

GCC_LIBOBJC_PATH="$($CC -print-file-name=libobjc-gnu.dylib 2>/dev/null || true)"
if [[ -z "$GCC_LIBOBJC_PATH" || "$GCC_LIBOBJC_PATH" == "libobjc-gnu.dylib" ]]; then
  GCC_LIBOBJC_PATH="$($CC -print-file-name=libobjc.dylib 2>/dev/null || true)"
fi
GCC_LIBGCC_S_PATH="$($CC -print-file-name=libgcc_s.1.1.dylib 2>/dev/null || true)"
GCC_LIBOBJC_DIR=""
GCC_LIBGCC_DIR=""
OBJC_RUNTIME_LIB_FLAG="-lobjc"

if [[ -n "$GCC_LIBOBJC_PATH" && "$GCC_LIBOBJC_PATH" != "libobjc.dylib" ]]; then
  GCC_LIBOBJC_DIR="$(dirname "$GCC_LIBOBJC_PATH")"
fi
if [[ "$GCC_LIBOBJC_PATH" == *"libobjc-gnu.dylib" ]]; then
  OBJC_RUNTIME_LIB_FLAG="-lobjc-gnu"
fi
if [[ -n "$GCC_LIBGCC_S_PATH" && "$GCC_LIBGCC_S_PATH" != "libgcc_s.1.1.dylib" ]]; then
  GCC_LIBGCC_DIR="$(dirname "$GCC_LIBGCC_S_PATH")"
fi

export PKG_CONFIG="$BREW_PREFIX/bin/pkg-config"
export PKG_CONFIG_PATH="$BREW_PREFIX/opt/icu4c/lib/pkgconfig:$BREW_PREFIX/opt/libxml2/lib/pkgconfig:$BREW_PREFIX/opt/libffi/lib/pkgconfig:$X11_PREFIX/lib/pkgconfig:$BREW_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export ACLOCAL_PATH="$BREW_PREFIX/share/aclocal:${ACLOCAL_PATH:-}"

# Bootstrap with Homebrew and XQuartz only. Do not expose an existing GNUstep
# prefix here because stale libobjc2 headers/libs can poison compiler probes.
export CPPFLAGS="-D__GNU_LIBOBJC__=1 -I$BREW_PREFIX/include -I$BREW_PREFIX/opt/icu4c/include -I$BREW_PREFIX/opt/libxml2/include -I$BREW_PREFIX/opt/libffi/include -I$X11_PREFIX/include ${CPPFLAGS:-}"
export LDFLAGS="-L$BREW_PREFIX/lib -L$BREW_PREFIX/opt/icu4c/lib -L$BREW_PREFIX/opt/libxml2/lib -L$BREW_PREFIX/opt/libffi/lib -L$X11_PREFIX/lib ${LDFLAGS:-}"

if [[ -n "$GCC_LIBOBJC_DIR" ]]; then
  export LDFLAGS="-L$GCC_LIBOBJC_DIR $LDFLAGS"
  export LDFLAGS="-Wl,-rpath,$GCC_LIBOBJC_DIR $LDFLAGS"
fi
if [[ -n "$GCC_LIBGCC_DIR" && "$GCC_LIBGCC_DIR" != "$GCC_LIBOBJC_DIR" ]]; then
  export LDFLAGS="-L$GCC_LIBGCC_DIR $LDFLAGS"
  export LDFLAGS="-Wl,-rpath,$GCC_LIBGCC_DIR $LDFLAGS"
fi

# Helpful runtime path for bootstrap tools built during the process.
export DYLD_LIBRARY_PATH="$BREW_PREFIX/lib:$X11_PREFIX/lib:${DYLD_LIBRARY_PATH:-}"
export LIBRARY_PATH="$BREW_PREFIX/lib:$X11_PREFIX/lib:${LIBRARY_PATH:-}"
export CPATH="$BREW_PREFIX/include:$X11_PREFIX/include:${CPATH:-}"

if [[ -n "$GCC_LIBOBJC_DIR" ]]; then
  export DYLD_LIBRARY_PATH="$GCC_LIBOBJC_DIR:$DYLD_LIBRARY_PATH"
  export LIBRARY_PATH="$GCC_LIBOBJC_DIR:$LIBRARY_PATH"
fi
if [[ -n "$GCC_LIBGCC_DIR" && "$GCC_LIBGCC_DIR" != "$GCC_LIBOBJC_DIR" ]]; then
  export DYLD_LIBRARY_PATH="$GCC_LIBGCC_DIR:$DYLD_LIBRARY_PATH"
  export LIBRARY_PATH="$GCC_LIBGCC_DIR:$LIBRARY_PATH"
fi

export CFLAGS="-D__GNU_LIBOBJC__=1 ${CFLAGS:-}"
export OBJCFLAGS="-D__GNU_LIBOBJC__=1 -fgnu-runtime ${OBJCFLAGS:-}"

purge_installed_libobjc2() {
  echo "==> Removing libobjc2 artifacts from $PREFIX"

  local targets=(
    "$PREFIX/System/Library/Headers/objc"
    "$PREFIX/Local/Library/Headers/objc"
    "$PREFIX/System/Library/Libraries/libobjc.4.6.dylib"
    "$PREFIX/System/Library/Libraries/libobjc.dylib"
    "$PREFIX/System/Library/Libraries/libobjc.a"
    "$PREFIX/System/Library/Libraries/pkgconfig/libobjc.pc"
    "$PREFIX/System/Library/Libraries/cmake/libobjc"
    "$PREFIX/Local/Library/Libraries/libobjc.4.6.dylib"
    "$PREFIX/Local/Library/Libraries/libobjc.dylib"
    "$PREFIX/Local/Library/Libraries/libobjc.a"
    "$PREFIX/Local/Library/Libraries/pkgconfig/libobjc.pc"
    "$PREFIX/Local/Library/Libraries/cmake/libobjc"
  )

  local existing=()
  local target
  for target in "${targets[@]}"; do
    if [[ -e "$target" ]]; then
      existing+=("$target")
    fi
  done

  if [[ ${#existing[@]} -eq 0 ]]; then
    return
  fi

  sudo rm -rf "${existing[@]}"
}

# Use a straightforward GNUstep layout under one prefix.
MAKE_CONFIGURE_FLAGS=(
  "--prefix=$PREFIX"
  "--with-layout=gnustep"
  "--disable-strip"
)

if [[ "$(uname -s)" == "Darwin" ]]; then
  MAKE_CONFIGURE_FLAGS+=(
    "--with-library-combo=gnu-gnu-gnu"
    "--with-objc-lib-flag=$OBJC_RUNTIME_LIB_FLAG"
    "--disable-objc-arc"
    "--enable-native-objc-exceptions"
  )
else
  MAKE_CONFIGURE_FLAGS+=(
    "--with-library-combo=gnu-gnu-gnu"
    "--enable-native-objc-exceptions"
  )
fi

LIB_CONFIGURE_FLAGS=(
  "--prefix=$PREFIX"
  "--disable-strip"
)

apply_preferred_compiler_env() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    export CC="$GCC_CC"
    export CXX="$GCC_CXX"
    export OBJC="$GCC_CC"
    export OBJCXX="$GCC_CXX"
  fi
}

source_gnustep_env() {
  # GNUstep.sh is not nounset-safe, so source it with -u temporarily disabled.
  local had_nounset=0

  if [[ $- == *u* ]]; then
    had_nounset=1
    set +u
  fi

  # shellcheck disable=SC1091
  . "$PREFIX/System/Library/Makefiles/GNUstep.sh"

  if [[ $had_nounset -eq 1 ]]; then
    set -u
  fi

  apply_preferred_compiler_env
}

check_objc_compiler() {
  echo "==> Checking Objective-C compiler/runtime"

  local probe_src
  local probe_bin
  probe_src="$(mktemp /tmp/gnustep-objc-check.XXXXXX.m)"
  probe_bin="$(mktemp /tmp/gnustep-objc-check.XXXXXX)"

  cat > "$probe_src" <<'EOF'
#include <objc/Object.h>
int main(void) { return 0; }
EOF

  if ! "$OBJC" $OBJCFLAGS "$probe_src" "$OBJC_RUNTIME_LIB_FLAG" $LDFLAGS -o "$probe_bin" >/tmp/gnustep-objc-probe.log 2>&1; then
    echo "Objective-C compile/link test failed with compiler: $OBJC"
    echo "OBJCFLAGS: ${OBJCFLAGS:-}"
    echo "OBJCLIB: $OBJC_RUNTIME_LIB_FLAG"
    tail -n 50 /tmp/gnustep-objc-probe.log || true
    rm -f "$probe_src" "$probe_bin"
    exit 1
  fi

  if ! "$probe_bin" >/dev/null 2>&1; then
    echo "Objective-C runtime execution test failed."
    echo "DYLD_LIBRARY_PATH: ${DYLD_LIBRARY_PATH:-}"
    rm -f "$probe_src" "$probe_bin"
    exit 1
  fi

  rm -f "$probe_src" "$probe_bin"
}

build_tools_make() {
  echo "==> Building tools-make"
  cd "$SRCROOT/tools-make"

  # tools-make installs scripts/makefiles directly after configure.
  make distclean >/dev/null 2>&1 || true

  local make_ccflags="${CCFLAGS:-}"

  CC="$CC" CXX="$CXX" CCFLAGS="$make_ccflags" ./configure "${MAKE_CONFIGURE_FLAGS[@]}"
  make debug=yes
  sudo make GNUSTEP_INSTALLATION_DOMAIN=SYSTEM debug=yes install

  echo "Sourcing $PREFIX/System/Library/Makefiles/GNUstep.sh"
  source_gnustep_env

  echo "GNUSTEP_MAKEFILES=$GNUSTEP_MAKEFILES"
  gnustep-config --variable=GNUSTEP_MAKEFILES
  echo "LIBRARY_COMBO=$(gnustep-config --variable=LIBRARY_COMBO)"
}

build_lib() {
  local name="$1"
  shift

  echo "==> Building $name"
  cd "$SRCROOT/$name"

  make distclean >/dev/null 2>&1 || true

  # Ensure GNUstep environment is loaded for all downstream builds.
  echo "Sourcing $PREFIX/System/Library/Makefiles/GNUstep.sh"
  source_gnustep_env

  export LDFLAGS="-L$PREFIX/System/Library/Libraries ${LDFLAGS:-}"
  export DYLD_LIBRARY_PATH="$PREFIX/System/Library/Libraries:${DYLD_LIBRARY_PATH:-}"
  export PKG_CONFIG_PATH="$PREFIX/System/Library/Libraries/pkgconfig:${PKG_CONFIG_PATH:-}"
  export CFLAGS="-I$PREFIX/System/Library/Headers ${CFLAGS:-}"

  ./configure "${LIB_CONFIGURE_FLAGS[@]}" "$@"
  make -j"$JOBS" debug=yes
  sudo make GNUSTEP_INSTALLATION_DOMAIN=SYSTEM debug=yes install
}

purge_installed_libobjc2
check_objc_compiler
build_tools_make


# Base first after make.
build_lib libs-base

# GUI next.
build_lib libs-gui \
  "--with-tiff-library=$BREW_PREFIX/lib"

# Back last; force X11-oriented include/library search paths.
build_lib libs-back \
  "--with-tiff-library=$BREW_PREFIX/lib"

# Refresh environment one last time.
source_gnustep_env

echo
echo "==> Build complete"
echo "Prefix: $PREFIX"
echo
echo "Add this to your shell profile:"
echo "  . \"$PREFIX/System/Library/Makefiles/GNUstep.sh\""
echo
echo "Sanity checks:"
echo "  gnustep-config --variable=GNUSTEP_MAKEFILES"
echo "  gnustep-config --gui-libs"
echo "  open -a XQuartz"
echo
echo "You may need to log out/in once after first installing XQuartz."
