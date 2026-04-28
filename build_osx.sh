#!/usr/bin/env sh
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
ZSH_VERSION=`zsh --version`

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
  libffi openssl@3 libxml2 icu4c zlib bdw-gc \
  jpeg-turbo libpng libtiff cairo fontconfig freetype \
  libx11 libxext libxt libxmu libxft libxrender libxfixes libxcursor libxrandr

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

# Common compiler and linker environment.
export CC="${CC:-clang}"
export CXX="${CXX:-clang++}"
export OBJC="${OBJC:-clang}"
export OBJCXX="${OBJCXX:-clang++}"

export PKG_CONFIG="$BREW_PREFIX/bin/pkg-config"
export PKG_CONFIG_PATH="$X11_PREFIX/lib/pkgconfig:$BREW_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export ACLOCAL_PATH="$BREW_PREFIX/share/aclocal:${ACLOCAL_PATH:-}"

# Put Homebrew and XQuartz first.
export CPPFLAGS="-I$PREFIX/include -I$BREW_PREFIX/include -I$X11_PREFIX/include ${CPPFLAGS:-}"
export LDFLAGS="-L$PREFIX/lib -L$BREW_PREFIX/lib -L$X11_PREFIX/lib ${LDFLAGS:-}"

# Helpful runtime path for tools built during the process.
export DYLD_LIBRARY_PATH="$PREFIX/lib:$BREW_PREFIX/lib:$X11_PREFIX/lib:${DYLD_LIBRARY_PATH:-}"
export LIBRARY_PATH="$PREFIX/lib:$BREW_PREFIX/lib:$X11_PREFIX/lib:${LIBRARY_PATH:-}"
export CPATH="$PREFIX/include:$BREW_PREFIX/include:$X11_PREFIX/include:${CPATH:-}"

# Use a straightforward GNUstep layout under one prefix.
MAKE_CONFIGURE_FLAGS=(
  "--prefix=$PREFIX"
  "--with-layout=gnustep"
  "--enable-native-objc-exceptions"
  "--disable-strip"
)

LIB_CONFIGURE_FLAGS=(
  "--prefix=$PREFIX"
  "--disable-strip"
)

build_tools_make() {
  echo "==> Building tools-make"
  cd "$SRCROOT/tools-make"

  # tools-make installs scripts/makefiles directly after configure.
  make distclean >/dev/null 2>&1 || true

  ./configure "${MAKE_CONFIGURE_FLAGS[@]}"
  make debug=yes
  sudo make GNUSTEP_INSTALLATION_DOMAIN=SYSTEM debug=yes install

  # shellcheck disable=SC1091
  unset ZSH_VERSION
  echo "Sourcing $PREFIX/System/Library/Makefiles/GNUstep.sh"
  . "$PREFIX/System/Library/Makefiles/GNUstep.sh"

  echo "GNUSTEP_MAKEFILES=$GNUSTEP_MAKEFILES"
  gnustep-config --variable=GNUSTEP_MAKEFILES
}

build_lib() {
  local name="$1"
  local extra_flags=("${@:2}")

  echo "==> Building $name"
  cd "$SRCROOT/$name"

  make distclean >/dev/null 2>&1 || true

  # Ensure GNUstep environment is loaded for all downstream builds.
  # shellcheck disable=SC1091
  echo "Sourcing $PREFIX/System/Library/Makefiles/GNUstep.sh"
  . "$PREFIX/System/Library/Makefiles/GNUstep.sh"

  ./configure "${LIB_CONFIGURE_FLAGS[@]}" "${extra_flags[@]}"
  make -j"$JOBS" debug=yes
  sudo make GNUSTEP_INSTALLATION_DOMAIN=SYSTEM debug=yes install
}

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
# shellcheck disable=SC1091
. "$PREFIX/System/Library/Makefiles/GNUstep.sh"

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
