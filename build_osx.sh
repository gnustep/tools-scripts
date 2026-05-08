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
  gcc make cmake ninja llvm \
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

if [[ ! -d libobjc2/.git ]]; then
  git clone "https://github.com/gnustep/libobjc2.git" libobjc2
fi

git -C libobjc2 fetch --all --prune
LIBOBJC2_BRANCH="$(git -C libobjc2 symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
if [[ -z "$LIBOBJC2_BRANCH" ]]; then
  LIBOBJC2_BRANCH=master
fi
git -C libobjc2 checkout "$LIBOBJC2_BRANCH"
git -C libobjc2 pull --ff-only origin "$LIBOBJC2_BRANCH"

patch_libobjc2_for_darwin() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    return
  fi

  local cmake_file="$SRCROOT/libobjc2/CMakeLists.txt"
  local aarch64_asm_file="$SRCROOT/libobjc2/objc_msgSend.aarch64.S"

  if grep -q -- '-fobjc-runtime=gnustep-' "$cmake_file"; then
    # Clang on modern Darwin can crash lowering COMDATs with forced GNUstep runtime.
    # For libobjc2 itself, rely on default Darwin runtime codegen.
    perl -0pi -e 's/;-fobjc-runtime=gnustep-[0-9]+\.[0-9]+//g' "$cmake_file"
  fi

  # Darwin arm64 assembler requires @PAGE and @PAGEOFF suffixes for symbol relocations
  if [[ -f "$aarch64_asm_file" ]]; then
    # Fix adrp: adrp x10, CDECL(SmallObjectClasses) -> adrp x10, CDECL(SmallObjectClasses)@PAGE
    perl -0pi -e 's/(adrp\s+x10,\s+CDECL\(SmallObjectClasses\))(?!@PAGE)/$1@PAGE/g' "$aarch64_asm_file"
    # Fix add: add x10, x10, CDECL(SmallObjectClasses) -> add x10, x10, CDECL(SmallObjectClasses)@PAGEOFF
    perl -0pi -e 's/(add\s+x10,\s+x10,\s+(?::lo12:)?CDECL\(SmallObjectClasses\))(?!@PAGEOFF)/$1@PAGEOFF/g' "$aarch64_asm_file"
  fi
}

patch_libobjc2_for_darwin

# Common compiler and linker environment.
HOMEBREW_LLVM_BIN="$BREW_PREFIX/opt/llvm/bin"
if [[ ! -x "$HOMEBREW_LLVM_BIN/clang" || ! -x "$HOMEBREW_LLVM_BIN/clang++" ]]; then
  echo "Homebrew LLVM clang not found at $HOMEBREW_LLVM_BIN"
  echo "Try: $BREW install llvm"
  exit 1
fi

export PATH="$HOMEBREW_LLVM_BIN:$BREW_PREFIX/opt/icu4c/bin:$BREW_PREFIX/opt/libxml2/bin:$PATH"
export CC="${CC:-$HOMEBREW_LLVM_BIN/clang}"
export CXX="${CXX:-$HOMEBREW_LLVM_BIN/clang++}"
export OBJC="${OBJC:-$HOMEBREW_LLVM_BIN/clang}"
export OBJCXX="${OBJCXX:-$HOMEBREW_LLVM_BIN/clang++}"

export CMAKE_C_COMPILER="$CC"
export CMAKE_CXX_COMPILER="$CXX"
export CMAKE_OBJC_COMPILER="$OBJC"
export CMAKE_OBJCXX_COMPILER="$OBJCXX"

LIBOBJC2_CC="$CC"
LIBOBJC2_CXX="$CXX"
LIBOBJC2_OBJC="$OBJC"
LIBOBJC2_OBJCXX="$OBJCXX"

if [[ "$(uname -s)" == "Darwin" && "${LIBOBJC2_USE_XCODE_CLANG:-1}" == "1" ]]; then
  LIBOBJC2_CC="/usr/bin/clang"
  LIBOBJC2_CXX="/usr/bin/clang++"
  LIBOBJC2_OBJC="/usr/bin/clang"
  LIBOBJC2_OBJCXX="/usr/bin/clang++"
fi

export PKG_CONFIG="$BREW_PREFIX/bin/pkg-config"
export PKG_CONFIG_PATH="$BREW_PREFIX/opt/icu4c/lib/pkgconfig:$BREW_PREFIX/opt/libxml2/lib/pkgconfig:$BREW_PREFIX/opt/libffi/lib/pkgconfig:$X11_PREFIX/lib/pkgconfig:$BREW_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export ACLOCAL_PATH="$BREW_PREFIX/share/aclocal:${ACLOCAL_PATH:-}"

# Put Homebrew and XQuartz first.
export CPPFLAGS="-I$PREFIX/System/Library/Headers -I$PREFIX/include -I$BREW_PREFIX/include -I$BREW_PREFIX/opt/icu4c/include -I$BREW_PREFIX/opt/libxml2/include -I$BREW_PREFIX/opt/libffi/include -I$X11_PREFIX/include ${CPPFLAGS:-}"
export LDFLAGS="-L$PREFIX/System/Library/Libraries -L$PREFIX/lib -L$BREW_PREFIX/lib -L$BREW_PREFIX/opt/icu4c/lib -L$BREW_PREFIX/opt/libxml2/lib -L$BREW_PREFIX/opt/libffi/lib -L$X11_PREFIX/lib ${LDFLAGS:-}"

# Helpful runtime path for tools built during the process.
export DYLD_LIBRARY_PATH="$PREFIX/System/Library/Libraries:$PREFIX/lib:$BREW_PREFIX/lib:$X11_PREFIX/lib:${DYLD_LIBRARY_PATH:-}"
export LIBRARY_PATH="$PREFIX/System/Library/Libraries:$PREFIX/lib:$BREW_PREFIX/lib:$X11_PREFIX/lib:${LIBRARY_PATH:-}"
export CPATH="$PREFIX/System/Library/Headers:$PREFIX/include:$BREW_PREFIX/include:$X11_PREFIX/include:${CPATH:-}"

# Use a straightforward GNUstep layout under one prefix.
MAKE_CONFIGURE_FLAGS=(
  "--prefix=$PREFIX"
  "--with-layout=gnustep"
  "--disable-strip"
)

if [[ "$(uname -s)" == "Darwin" ]]; then
  MAKE_CONFIGURE_FLAGS+=(
    "--with-library-combo=ng-gnu-gnu"
    "--with-runtime-abi=gnustep-1.8"
    "--with-objc-lib-flag=-lobjc"
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
    export CC="$HOMEBREW_LLVM_BIN/clang"
    export CXX="$HOMEBREW_LLVM_BIN/clang++"
    export OBJC="$HOMEBREW_LLVM_BIN/clang"
    export OBJCXX="$HOMEBREW_LLVM_BIN/clang++"
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

build_tools_make() {
  echo "==> Building tools-make"
  cd "$SRCROOT/tools-make"

  # tools-make installs scripts/makefiles directly after configure.
  make distclean >/dev/null 2>&1 || true

  local make_ccflags="${CCFLAGS:-}"
  if [[ "$(uname -s)" == "Darwin" ]]; then
    make_ccflags="-fblocks -fobjc-nonfragile-abi ${make_ccflags}"
  fi

  CC="$CC" CXX="$CXX" CCFLAGS="$make_ccflags" ./configure "${MAKE_CONFIGURE_FLAGS[@]}"
  make debug=yes
  sudo make GNUSTEP_INSTALLATION_DOMAIN=SYSTEM debug=yes install

  echo "Sourcing $PREFIX/System/Library/Makefiles/GNUstep.sh"
  source_gnustep_env

  echo "GNUSTEP_MAKEFILES=$GNUSTEP_MAKEFILES"
  gnustep-config --variable=GNUSTEP_MAKEFILES
  echo "LIBRARY_COMBO=$(gnustep-config --variable=LIBRARY_COMBO)"
}

build_libobjc2() {
  echo "==> Building libobjc2 ($LIBOBJC2_BRANCH)"
  cd "$SRCROOT/libobjc2"

  rm -rf build
  mkdir -p build
  cd build

  # On macOS, disable compact unwind to avoid "too many personality routines" error
  # Use -Wl, prefix to pass to linker with proper escaping
  local LINKER_FLAGS=""
  if [[ "$(uname -s)" == "Darwin" ]]; then
    LINKER_FLAGS="-Wl,-no_compact_unwind"
  fi

  cmake .. \
    -G Ninja \
    -Wno-dev \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DGNUSTEP_INSTALL_TYPE=SYSTEM \
    -DCMAKE_C_COMPILER="$LIBOBJC2_CC" \
    -DCMAKE_CXX_COMPILER="$LIBOBJC2_CXX" \
    -DCMAKE_OBJC_COMPILER="$LIBOBJC2_OBJC" \
    -DCMAKE_OBJCXX_COMPILER="$LIBOBJC2_OBJCXX" \
    -DCMAKE_ASM_COMPILER="$LIBOBJC2_CC" \
    -DCMAKE_EXE_LINKER_FLAGS="$LINKER_FLAGS" \
    -DCMAKE_SHARED_LINKER_FLAGS="$LINKER_FLAGS" \
    -DCMAKE_MODULE_LINKER_FLAGS="$LINKER_FLAGS" \
    -DCMAKE_PREFIX_PATH="$BREW_PREFIX;$PREFIX"

  ninja -j"$JOBS"
  sudo ninja install

  if [[ "$(uname -s)" == "Darwin" ]]; then
    local objc_dylib="$PREFIX/System/Library/Libraries/libobjc.4.6.dylib"
    if [[ -f "$objc_dylib" ]]; then
      # Avoid @rpath runtime lookup failures in configure test executables.
      sudo install_name_tool -id "$objc_dylib" "$objc_dylib"
    fi
  fi

  echo "libobjc2 local libs: $(gnustep-config --variable=GNUSTEP_LOCAL_LIBRARIES)"
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

  if [[ "$(uname -s)" == "Darwin" && "$name" == "libs-base" ]]; then
    local cache_file="$SRCROOT/$name/config.cache"
    cat > "$cache_file" <<'EOF'
gs_cv_objc_works=yes
gs_cv_objc_load_method_worked=yes
gs_cv_objc_compiler_supports_constant_string_class=yes
EOF
    ./configure --cache-file="$cache_file" "${LIB_CONFIGURE_FLAGS[@]}" "$@"
  else
    ./configure "${LIB_CONFIGURE_FLAGS[@]}" "$@"
  fi
  make -j"$JOBS" debug=yes
  sudo make GNUSTEP_INSTALLATION_DOMAIN=SYSTEM debug=yes install
}

build_tools_make
build_libobjc2

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
