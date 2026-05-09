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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_SRCROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
if [[ ! -d "$DEFAULT_SRCROOT/tools-make" || ! -d "$DEFAULT_SRCROOT/libs-base" || ! -d "$DEFAULT_SRCROOT/libs-gui" || ! -d "$DEFAULT_SRCROOT/libs-back" ]]; then
  DEFAULT_SRCROOT="$HOME/src/gnustep-core"
fi
SRCROOT="${SRCROOT:-$DEFAULT_SRCROOT}"
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

reset_patch_targets() {
  if [[ -d "$SRCROOT/tools-make/.git" ]]; then
    git -C "$SRCROOT/tools-make" checkout -- target.make
  fi

  if [[ -d "$SRCROOT/libs-base/.git" ]]; then
    git -C "$SRCROOT/libs-base" checkout -- \
      Headers/Foundation/Foundation.h \
      Tools/gdomap.c \
      Source/NSNotificationCenter.m \
      Source/NSObject.m \
      Source/NSZone.m \
      Source/NSAutoreleasePool.m
  fi

  if [[ -d "$SRCROOT/libs-gui/.git" ]]; then
    git -C "$SRCROOT/libs-gui" checkout -- \
      Tools/gclose.m \
      Tools/gcloseall.m \
      Tools/gopen.m \
      Tools/make_services.m \
      Tools/set_show_service.m
  fi

  if [[ -d "$SRCROOT/libs-back/.git" ]]; then
    git -C "$SRCROOT/libs-back" checkout -- \
      Tools/font_cacher.m \
      Tools/gpbs.m
  fi
}

patch_tools_make_for_darwin_gcc() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    return
  fi

  local target_make="$SRCROOT/tools-make/target.make"

  if [[ -f "$target_make" ]]; then
    perl -0pi -e 's/-Wl,-noall_load\s+//g' "$target_make"
  fi
}

patch_libs_base_for_darwin_gcc() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    return
  fi

  local foundation_header="$SRCROOT/libs-base/Headers/Foundation/Foundation.h"

  if [[ -f "$foundation_header" ]]; then
    perl -0pi -e 's/#ifdef __has_include\n#  if __has_include\(<CoreFoundation\/CoreFoundation\.h>\)\n#    include <CoreFoundation\/CoreFoundation\.h>\n#  endif\n#  if __has_include\(<dispatch\/dispatch\.h>\)\n#    include <dispatch\/dispatch\.h>\n#  endif\n#endif/#if defined(__has_include) \&\& !defined(__GNU_LIBOBJC__)\n#  if __has_include(<CoreFoundation\/CoreFoundation.h>)\n#    include <CoreFoundation\/CoreFoundation.h>\n#  endif\n#  if __has_include(<dispatch\/dispatch.h>)\n#    include <dispatch\/dispatch.h>\n#  endif\n#endif/g' "$foundation_header"
  fi
}

patch_gdomap_for_modern_sdk() {
  local gdomap="$SRCROOT/libs-base/Tools/gdomap.c"
  if [[ ! -f "$gdomap" ]]; then
    return
  fi

  perl -pi -e 's/^(static void\s+dump_tables)\(\);$/$1(int sig);/' "$gdomap"
  perl -pi -e 's/^(dump_tables)\(\)$/$1(int sig)/' "$gdomap"
  perl -pi -e 's/void\s+\(\*ifun\)\(\)/void (*ifun)(int)/' "$gdomap"
}

patch_nsobject_for_gnu_runtime() {
  local nsobject="$SRCROOT/libs-base/Source/NSObject.m"
  if [[ ! -f "$nsobject" ]]; then
    return
  fi

  if rg -q 'extern BOOL[[:space:]]+objc_create_block_classes_as_subclasses_of\(Class super\);' "$nsobject"; then
    perl -0pi -e 's|(extern BOOL\s+objc_create_block_classes_as_subclasses_of\(Class super\);)|#ifndef __GNU_LIBOBJC__\n$1\n#endif|g' "$nsobject"
  fi
  if rg -q '^\s+objc_create_block_classes_as_subclasses_of\(self\);' "$nsobject"; then
    perl -pi -e 's|^(\s+)(objc_create_block_classes_as_subclasses_of\(self\);)|$1#ifndef __GNU_LIBOBJC__\n$1$2\n$1#endif|' "$nsobject"
  fi
  if rg -q '^\s+GSWeakInit\(\);' "$nsobject"; then
    perl -pi -e 's|^(\s+)(GSWeakInit\(\);)|$1#ifndef __GNU_LIBOBJC__\n$1$2\n$1#endif|' "$nsobject"
  fi
  if rg -q '^\s+objc_delete_weak_refs\(anObject\);' "$nsobject"; then
    perl -pi -e 's|^(\s+)(objc_delete_weak_refs\(anObject\);)|$1#ifndef __GNU_LIBOBJC__\n$1$2\n$1#endif|' "$nsobject"
  fi
}

patch_nsnotificationcenter_for_gnu_runtime() {
  local center="$SRCROOT/libs-base/Source/NSNotificationCenter.m"
  if [[ ! -f "$center" ]]; then
    return
  fi

  if ! rg -q 'GSNotificationObserverInit' "$center"; then
    perl -0pi -e 's|(#define\s+ENDOBS\s+\(\(Observation\*\)-1\)\n)|$1\n#if defined(__GNU_LIBOBJC__)\nstatic inline void\nGSNotificationObserverInit(id *slot, id value)\n{\n  *slot = value;\n}\n\nstatic inline id\nGSNotificationObserverLoad(id *slot)\n{\n  return *slot;\n}\n\nstatic inline id\nGSNotificationObserverLoadRetained(id *slot)\n{\n  return [*slot retain];\n}\n\nstatic inline void\nGSNotificationObserverDestroy(id *slot)\n{\n  *slot = nil;\n}\n#else\nstatic inline void\nGSNotificationObserverInit(id *slot, id value)\n{\n  objc_initWeak(slot, value);\n}\n\nstatic inline id\nGSNotificationObserverLoad(id *slot)\n{\n  return objc_loadWeak(slot);\n}\n\nstatic inline id\nGSNotificationObserverLoadRetained(id *slot)\n{\n  return objc_loadWeakRetained(slot);\n}\n\nstatic inline void\nGSNotificationObserverDestroy(id *slot)\n{\n  objc_destroyWeak(slot);\n}\n#endif\n|s' "$center"
  fi

  perl -0pi -e 's/objc_initWeak\(&obs->observer, o\);/GSNotificationObserverInit\(&obs->observer, o\);/g' "$center"
  perl -0pi -e 's/objc_loadWeak\(&o->observer\)/GSNotificationObserverLoad\(&o->observer\)/g' "$center"
  perl -0pi -e 's/objc_destroyWeak\(&o->observer\);/GSNotificationObserverDestroy\(&o->observer\);/g' "$center"
  perl -0pi -e 's/objc_loadWeak\(&list->observer\)/GSNotificationObserverLoad\(&list->observer\)/g' "$center"
  perl -0pi -e 's/objc_loadWeak\(&tmp->next->observer\)/GSNotificationObserverLoad\(&tmp->next->observer\)/g' "$center"
  perl -0pi -e 's/objc_loadWeakRetained\(&o->observer\)/GSNotificationObserverLoadRetained\(&o->observer\)/g' "$center"
}

patch_nszone_for_darwin_gcc() {
  local nszone="$SRCROOT/libs-base/Source/NSZone.m"
  if [[ ! -f "$nszone" ]]; then
    return
  fi

  perl -0pi -e 's/default_stats, 0, @"default", 0/default_stats, 0, 0, 0/g' "$nszone"

  if ! grep -q 'init_default_zone_name' "$nszone"; then
    perl -0pi -e 's|(static NSZone default_zone =\n\{\n\s*default_malloc, default_realloc, default_free, default_recycle,\n\s*default_check, default_lookup, default_stats, 0, 0, 0\n\};\n)|$1\n__attribute__((constructor)) static void\ninit_default_zone_name (void)\n{\n  default_zone.name = @"default";\n}\n|s' "$nszone"
  fi

  perl -0pi -e 's~GS_DECLARE void\*\nNSZoneMalloc \(NSZone \*zone, NSUInteger size\)\n\{\n  if \(!zone\)\n    zone = NSDefaultMallocZone\(\);\n  return \(zone->malloc\)\(zone, size\);\n\}~GS_DECLARE void*\nNSZoneMalloc (NSZone *zone, NSUInteger size)\n{\n  if (!zone || zone == NSDefaultMallocZone())\n    return default_malloc(NSDefaultMallocZone(), size);\n  return (zone->malloc)(zone, size);\n\}~s' "$nszone"
}

patch_nsautoreleasepool_for_gnu_runtime() {
  local arp="$SRCROOT/libs-base/Source/NSAutoreleasePool.m"
  if [[ ! -f "$arp" ]]; then
    return
  fi

  if ! rg -q 'GSAutoreleasePointerLooksValid' "$arp"; then
    perl -0pi -e 's~/\* Easy access to the thread variables belonging to NSAutoreleasePool\. \*/\n#define ARP_THREAD_VARS \(&\(\(GSCurrentThread\(\)\)\->_autorelease_vars\)\)~/* Easy access to the thread variables belonging to NSAutoreleasePool. */\n#define ARP_THREAD_VARS (&((GSCurrentThread())->_autorelease_vars))\n\n#if defined(__APPLE__) && defined(__GNU_LIBOBJC__)\nstatic inline BOOL\nGSAutoreleasePointerLooksValid(const void *pointer)\n{\n  uintptr_t value = (uintptr_t)pointer;\n\n  if (value == 0)\n    {\n      return NO;\n    }\n  if ((value & 0x7) != 0)\n    {\n      return NO;\n    }\n  return ((value >> 48) == 0 || (value >> 48) == 0xffff);\n}\n#endif~s' "$arp"
  fi

  if rg -q 'c = object_getClass\(anObject\);' "$arp" && ! rg -q 'invalid class encountered in autorelease pool' "$arp"; then
    perl -0pi -e 's|\t      anObject = objects\[i\];\n\t      objects\[i\] = nil;\n              if \(anObject == nil\)\n                \{\n                  fprintf\(stderr,\n                    "nil object encountered in autorelease pool\\n"\);\n                  continue;\n                \}\n\t      c = object_getClass\(anObject\);\n              if \(c == 0\)\n                \{\n                  \[NSException raise: NSInternalInconsistencyException\n                    format: \@"nul class for object in autorelease pool"\];\n                \}|\t      anObject = objects[i];\n\t      objects[i] = nil;\n              if (anObject == nil)\n                {\n                  fprintf(stderr,\n                    "nil object encountered in autorelease pool\\n");\n                  continue;\n                }\n\t      #if defined(__APPLE__) && defined(__GNU_LIBOBJC__)\n\t      if (NO == GSAutoreleasePointerLooksValid(anObject))\n\t        {\n\t          volatile struct autorelease_array_list *remaining = released;\n\n\t          fprintf(stderr,\n\t            "invalid object encountered in autorelease pool: %p\\n",\n\t            anObject);\n\t          while (remaining != 0)\n\t            {\n\t              remaining->count = 0;\n\t              remaining = remaining->next;\n\t            }\n\t          _released_count = 0;\n\t          break;\n\t        }\n\t      #endif\n\t      c = object_getClass(anObject);\n              if (c == 0)\n                {\n                  [NSException raise: NSInternalInconsistencyException\n                    format: @"nul class for object in autorelease pool"];\n                }\n\t      #if defined(__APPLE__) && defined(__GNU_LIBOBJC__)\n\t      if (NO == GSAutoreleasePointerLooksValid(c))\n\t        {\n\t          volatile struct autorelease_array_list *remaining = released;\n\n\t          fprintf(stderr,\n\t            "invalid class encountered in autorelease pool: object=%p class=%p\\n",\n\t            anObject, c);\n\t          while (remaining != 0)\n\t            {\n\t              remaining->count = 0;\n\t              remaining = remaining->next;\n\t            }\n\t          _released_count = 0;\n\t          break;\n\t        }\n\t      #endif|s' "$arp"
  fi

  perl -pi -e 's/NSAllocateObject \(self, 0, zone\)/NSAllocateObject (self, 0, NULL)/g' "$arp"

  if rg -q '^\+ \(id\) new$' "$arp"; then
    perl -0pi -e 's|\+ \(id\) new\n\{\n  static IMP\s+allocImp = 0;\n  static IMP\s+initImp = 0;\n  id\s+arp;\n\n  if \(0 == allocImp\)\n    \{\n      allocImp\n\s*= \[NSAutoreleasePool methodForSelector: \@selector\(allocWithZone:\)\];\n      initImp\n\s*= \[NSAutoreleasePool instanceMethodForSelector: \@selector\(init\)\];\n    \}\n  arp = \(\*allocImp\)\(self, \@selector\(allocWithZone:\), NSDefaultMallocZone\(\)\);\n  return \(\*initImp\)\(arp, \@selector\(init\)\);\n\}|+ (id) new\n{\n  return [[self allocWithZone: NULL] init];\n}|s' "$arp"
  fi
}

patch_nsautoreleasepool_runtime_safety() {
  local arp="$SRCROOT/libs-base/Source/NSAutoreleasePool.m"
  if [[ ! -f "$arp" ]]; then
    return
  fi

  perl -0pi -e 's|#if defined\(__APPLE__\) && defined\(__GNU_LIBOBJC__\)\n\s*if \(NO == GSAutoreleasePointerLooksValid\(anObject\)\)\n\s*\{\n\s*volatile struct autorelease_array_list \*remaining = released;\n\n\s*fprintf\(stderr,\n\s*"invalid object encountered in autorelease pool: %p\\n",\n\s*anObject\);\n\s*while \(remaining != 0\)\n\s*\{\n\s*remaining->count = 0;\n\s*remaining = remaining->next;\n\s*\}\n\s*_released_count = 0;\n\s*break;\n\s*\}\n\s*#endif|#if defined(__APPLE__) && defined(__GNU_LIBOBJC__)\n      if (NO == GSAutoreleasePointerLooksValid(anObject))\n        {\n          fprintf(stderr,\n            "invalid object encountered in autorelease pool: %p\\n",\n            anObject);\n          continue;\n        }\n      #endif|s; s|#if defined\(__APPLE__\) && defined\(__GNU_LIBOBJC__\)\n\s*if \(NO == GSAutoreleasePointerLooksValid\(c\)\)\n\s*\{\n\s*volatile struct autorelease_array_list \*remaining = released;\n\n\s*fprintf\(stderr,\n\s*"invalid class encountered in autorelease pool: object=%p class=%p\\n",\n\s*anObject, c\);\n\s*while \(remaining != 0\)\n\s*\{\n\s*remaining->count = 0;\n\s*remaining = remaining->next;\n\s*\}\n\s*_released_count = 0;\n\s*break;\n\s*\}\n\s*#endif|#if defined(__APPLE__) && defined(__GNU_LIBOBJC__)\n      if (NO == GSAutoreleasePointerLooksValid(c))\n        {\n          fprintf(stderr,\n            "invalid class encountered in autorelease pool: object=%p class=%p\\n",\n            anObject, c);\n          continue;\n        }\n      #endif|s' "$arp"
}

patch_tool_processinfo_init_guards() {
  local roots=(
    "$SRCROOT/libs-base/Tools"
    "$SRCROOT/libs-gui/Tools"
    "$SRCROOT/libs-back/Tools"
  )

  local root
  local file
  for root in "${roots[@]}"; do
    [[ -d "$root" ]] || continue

    while IFS= read -r file; do
      perl -0pi -e 's|#ifdef GS_PASS_ARGUMENTS\n([ \t]*\[NSProcessInfo initializeWithArguments:[^\n]*\];)\n[ \t]*#endif|$1|g' "$file"
    done < <(rg -l '#ifdef GS_PASS_ARGUMENTS' "$root")
  done
}

reset_patch_targets
patch_tools_make_for_darwin_gcc
patch_libs_base_for_darwin_gcc
patch_gdomap_for_modern_sdk
patch_nsobject_for_gnu_runtime
patch_nsnotificationcenter_for_gnu_runtime
patch_nszone_for_darwin_gcc
patch_nsautoreleasepool_for_gnu_runtime
patch_nsautoreleasepool_runtime_safety
patch_tool_processinfo_init_guards

# Common compiler and linker environment: GCC + GNU Objective-C runtime only.
GCC_CC="$(ls -1 "$BREW_PREFIX"/bin/gcc-[0-9]* 2>/dev/null | sort -V | tail -n1)"
GCC_CXX="$(ls -1 "$BREW_PREFIX"/bin/g++-[0-9]* 2>/dev/null | sort -V | tail -n1)"

if [[ -z "$GCC_CC" || -z "$GCC_CXX" ]]; then
  echo "Homebrew GCC not found under $BREW_PREFIX/bin"
  echo "Try: $BREW install gcc"
  exit 1
fi
export CC="$GCC_CC"
export CXX="$GCC_CXX"
export OBJC="$GCC_CC"
export OBJCXX="$GCC_CXX"

GCC_LIBOBJC_PATH="$($CC -print-file-name=libobjc-gnu.dylib 2>/dev/null || true)"
GCC_LIBGCC_S_PATH="$($CC -print-file-name=libgcc_s.1.1.dylib 2>/dev/null || true)"
GCC_CELLAR_DIR="$($BREW --cellar gcc 2>/dev/null || true)"
GCC_GNU_RUNTIME_HEADER=""
GCC_LIBOBJC_DIR=""
GCC_LIBGCC_DIR=""
GCC_GNU_RUNTIME_INCLUDE_DIR=""
OBJC_RUNTIME_LIB_FLAG="-lobjc-gnu"

if [[ -n "$GCC_LIBOBJC_PATH" && "$GCC_LIBOBJC_PATH" != "libobjc-gnu.dylib" ]]; then
  GCC_LIBOBJC_DIR="$(dirname "$GCC_LIBOBJC_PATH")"
fi
if [[ -z "$GCC_LIBOBJC_DIR" ]]; then
  echo "Homebrew GCC GNU Objective-C runtime not found."
  echo "Expected libobjc-gnu.dylib via: $CC -print-file-name=libobjc-gnu.dylib"
  exit 1
fi
if [[ -d "$GCC_CELLAR_DIR" ]]; then
  GCC_GNU_RUNTIME_HEADER="$(find "$GCC_CELLAR_DIR" -path '*include-gnu-runtime/objc/runtime.h' | sort | tail -n1)"
fi
if [[ -n "$GCC_GNU_RUNTIME_HEADER" ]]; then
  GCC_GNU_RUNTIME_INCLUDE_DIR="$(dirname "$(dirname "$GCC_GNU_RUNTIME_HEADER")")"
fi
if [[ -z "$GCC_GNU_RUNTIME_INCLUDE_DIR" ]]; then
  echo "Homebrew GCC GNU Objective-C runtime headers not found."
  echo "Expected include-gnu-runtime/objc/runtime.h under: $GCC_CELLAR_DIR"
  exit 1
fi
if [[ -n "$GCC_LIBGCC_S_PATH" && "$GCC_LIBGCC_S_PATH" != "libgcc_s.1.1.dylib" ]]; then
  GCC_LIBGCC_DIR="$(dirname "$GCC_LIBGCC_S_PATH")"
fi

echo "==> Using GNU Objective-C runtime from $GCC_LIBOBJC_DIR"
echo "==> Using GNU Objective-C headers from $GCC_GNU_RUNTIME_INCLUDE_DIR"

export PKG_CONFIG="$BREW_PREFIX/bin/pkg-config"
export PKG_CONFIG_PATH="$BREW_PREFIX/opt/icu4c/lib/pkgconfig:$BREW_PREFIX/opt/libxml2/lib/pkgconfig:$BREW_PREFIX/opt/libffi/lib/pkgconfig:$X11_PREFIX/lib/pkgconfig:$BREW_PREFIX/lib/pkgconfig${EXTRA_PKG_CONFIG_PATH:+:$EXTRA_PKG_CONFIG_PATH}"
export ACLOCAL_PATH="$BREW_PREFIX/share/aclocal${EXTRA_ACLOCAL_PATH:+:$EXTRA_ACLOCAL_PATH}"

# Bootstrap with Homebrew and XQuartz only. Do not expose an existing GNUstep
# prefix here because stale libobjc2 headers/libs can poison compiler probes.
export CPPFLAGS="-D__GNU_LIBOBJC__=1 -I$GCC_GNU_RUNTIME_INCLUDE_DIR -I$BREW_PREFIX/include -I$BREW_PREFIX/opt/icu4c/include -I$BREW_PREFIX/opt/libxml2/include -I$BREW_PREFIX/opt/libffi/include -I$X11_PREFIX/include${EXTRA_CPPFLAGS:+ $EXTRA_CPPFLAGS}"
export LDFLAGS="-L$BREW_PREFIX/lib -L$BREW_PREFIX/opt/icu4c/lib -L$BREW_PREFIX/opt/libxml2/lib -L$BREW_PREFIX/opt/libffi/lib -L$X11_PREFIX/lib${EXTRA_LDFLAGS:+ $EXTRA_LDFLAGS}"

if [[ -n "$GCC_LIBOBJC_DIR" ]]; then
  export LDFLAGS="-L$GCC_LIBOBJC_DIR $LDFLAGS"
  export LDFLAGS="-Wl,-rpath,$GCC_LIBOBJC_DIR $LDFLAGS"
fi
if [[ -n "$GCC_LIBGCC_DIR" && "$GCC_LIBGCC_DIR" != "$GCC_LIBOBJC_DIR" ]]; then
  export LDFLAGS="-L$GCC_LIBGCC_DIR $LDFLAGS"
  export LDFLAGS="-Wl,-rpath,$GCC_LIBGCC_DIR $LDFLAGS"
fi

# Helpful runtime path for bootstrap tools built during the process.
export DYLD_LIBRARY_PATH="$BREW_PREFIX/lib:$X11_PREFIX/lib${EXTRA_DYLD_LIBRARY_PATH:+:$EXTRA_DYLD_LIBRARY_PATH}"
export LIBRARY_PATH="$BREW_PREFIX/lib:$X11_PREFIX/lib${EXTRA_LIBRARY_PATH:+:$EXTRA_LIBRARY_PATH}"
export CPATH="$GCC_GNU_RUNTIME_INCLUDE_DIR:$BREW_PREFIX/include:$X11_PREFIX/include${EXTRA_CPATH:+:$EXTRA_CPATH}"

if [[ -n "$GCC_LIBOBJC_DIR" ]]; then
  export DYLD_LIBRARY_PATH="$GCC_LIBOBJC_DIR:$DYLD_LIBRARY_PATH"
  export LIBRARY_PATH="$GCC_LIBOBJC_DIR:$LIBRARY_PATH"
fi
if [[ -n "$GCC_LIBGCC_DIR" && "$GCC_LIBGCC_DIR" != "$GCC_LIBOBJC_DIR" ]]; then
  export DYLD_LIBRARY_PATH="$GCC_LIBGCC_DIR:$DYLD_LIBRARY_PATH"
  export LIBRARY_PATH="$GCC_LIBGCC_DIR:$LIBRARY_PATH"
fi

export CFLAGS="-D__GNU_LIBOBJC__=1${EXTRA_CFLAGS:+ $EXTRA_CFLAGS}"
export OBJCFLAGS="-D__GNU_LIBOBJC__=1 -fgnu-runtime${EXTRA_OBJCFLAGS:+ $EXTRA_OBJCFLAGS}"
export GNUSTEP_MAKE_SERVICES="${GNUSTEP_MAKE_SERVICES:-/usr/bin/true}"

BASE_PKG_CONFIG="$PKG_CONFIG"
BASE_PKG_CONFIG_PATH="$PKG_CONFIG_PATH"
BASE_ACLOCAL_PATH="$ACLOCAL_PATH"
BASE_CPPFLAGS="$CPPFLAGS"
BASE_LDFLAGS="$LDFLAGS"
BASE_DYLD_LIBRARY_PATH="$DYLD_LIBRARY_PATH"
BASE_LIBRARY_PATH="$LIBRARY_PATH"
BASE_CPATH="$CPATH"
BASE_CFLAGS="$CFLAGS"
BASE_OBJCFLAGS="$OBJCFLAGS"

reset_bootstrap_env() {
  export PKG_CONFIG="$BASE_PKG_CONFIG"
  export PKG_CONFIG_PATH="$BASE_PKG_CONFIG_PATH"
  export ACLOCAL_PATH="$BASE_ACLOCAL_PATH"
  export CPPFLAGS="$BASE_CPPFLAGS"
  export LDFLAGS="$BASE_LDFLAGS"
  export DYLD_LIBRARY_PATH="$BASE_DYLD_LIBRARY_PATH"
  export LIBRARY_PATH="$BASE_LIBRARY_PATH"
  export CPATH="$BASE_CPATH"
  export CFLAGS="$BASE_CFLAGS"
  export OBJCFLAGS="$BASE_OBJCFLAGS"
  apply_preferred_compiler_env
}

run_as_root() {
  if [[ -n "${SUDO_ASKPASS:-}" ]]; then
    sudo -A "$@"
  else
    sudo "$@"
  fi
}

ensure_prefix_permissions() {
  local dirs=(
    "$PREFIX"
    "$PREFIX/System"
    "$PREFIX/System/Library"
    "$PREFIX/System/Library/Headers"
    "$PREFIX/System/Library/Libraries"
    "$PREFIX/Local"
    "$PREFIX/Local/Library"
    "$PREFIX/Local/Library/Headers"
    "$PREFIX/Local/Library/Libraries"
    "$PREFIX/Local/Library/Libraries/pkgconfig"
  )

  local existing=()
  local dir
  for dir in "${dirs[@]}"; do
    if [[ -d "$dir" ]]; then
      existing+=("$dir")
    fi
  done

  if [[ ${#existing[@]} -gt 0 ]]; then
    run_as_root chmod 755 "${existing[@]}"
  fi

  local trees=(
    "$PREFIX/System/Library/Headers"
    "$PREFIX/System/Library/Libraries"
    "$PREFIX/Local/Library/Headers"
    "$PREFIX/Local/Library/Libraries"
  )

  local tree
  for tree in "${trees[@]}"; do
    if [[ -d "$tree" ]]; then
      run_as_root find "$tree" -type d -exec chmod 755 {} +
      run_as_root find "$tree" -type f -exec chmod 644 {} +
    fi
  done
}

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

  run_as_root rm -rf "${existing[@]}"
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

  reset_bootstrap_env

  local make_ccflags="${CCFLAGS:-}"

  CC="$CC" CXX="$CXX" CCFLAGS="$make_ccflags" ./configure "${MAKE_CONFIGURE_FLAGS[@]}"
  make GNUSTEP_INSTALLATION_DOMAIN=SYSTEM debug=yes
  run_as_root make GNUSTEP_INSTALLATION_DOMAIN=SYSTEM debug=yes install
  ensure_prefix_permissions

  if [[ "$(uname -s)" == "Darwin" ]]; then
    local installed_target_make="$PREFIX/System/Library/Makefiles/target.make"
    if [[ -f "$installed_target_make" ]]; then
      run_as_root perl -0pi -e 's/-Wl,-noall_load\s+//g' "$installed_target_make"
    fi
  fi

  echo "Sourcing $PREFIX/System/Library/Makefiles/GNUstep.sh"
  source_gnustep_env

  echo "GNUSTEP_MAKEFILES=$GNUSTEP_MAKEFILES"
  gnustep-config --variable=GNUSTEP_MAKEFILES
  echo "LIBRARY_COMBO=$(gnustep-config --variable=LIBRARY_COMBO)"
}

build_lib() {
  local name="$1"
  shift
  local extra_args=("$@")

  echo "==> Building $name"
  cd "$SRCROOT/$name"

  make distclean >/dev/null 2>&1 || true

  # Ensure GNUstep environment is loaded for all downstream builds.
  echo "Sourcing $PREFIX/System/Library/Makefiles/GNUstep.sh"
  source_gnustep_env

  reset_bootstrap_env

  export CPPFLAGS="-I$PREFIX/System/Library/Headers $CPPFLAGS"
  export LDFLAGS="-L$PREFIX/System/Library/Libraries $LDFLAGS"
  export DYLD_LIBRARY_PATH="$PREFIX/System/Library/Libraries:$DYLD_LIBRARY_PATH"
  export PKG_CONFIG_PATH="$PREFIX/System/Library/Libraries/pkgconfig:$PKG_CONFIG_PATH"

  if [[ "$name" == "libs-base" ]]; then
    extra_args+=("--disable-libdispatch")
    extra_args+=("--disable-importing-config-file")
  fi

  ./configure "${LIB_CONFIGURE_FLAGS[@]}" "${extra_args[@]}"
  make -j"$JOBS" GNUSTEP_INSTALLATION_DOMAIN=SYSTEM debug=yes
  run_as_root make GNUSTEP_INSTALLATION_DOMAIN=SYSTEM debug=yes install
  ensure_prefix_permissions
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
