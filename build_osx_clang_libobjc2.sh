#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# GNUstep clean build for macOS using clang + libobjc2 and the system X11
# installation
#
# Builds and installs:
#   - tools-make
#   - libs-base
#   - libs-gui
#   - libs-back
#
# Notes:
#   * XQuartz is the standard system X11 installation on modern macOS and is
#     expected at /opt/X11 unless X11_PREFIX is set.
#   * Homebrew provides non-X11 build dependencies and can install the XQuartz
#     cask if the system X11 tree is missing.
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
LIBOBJC2_TAG="${LIBOBJC2_TAG:-v2.3}"

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
REQUESTED_X11_PREFIX="${X11_PREFIX:-}"

# System/XQuartz X11 paths.  The user may set X11_PREFIX explicitly; otherwise
# prefer the standard XQuartz location and then the historical Apple X11 paths.
detect_x11_prefix() {
  local candidates=()
  if [[ -n "$REQUESTED_X11_PREFIX" ]]; then
    candidates+=("$REQUESTED_X11_PREFIX")
  fi
  candidates+=(
    "/opt/X11"
    "/usr/X11"
    "/usr/X11R6"
    "/usr/local/X11"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate/include/X11/Xlib.h" ]] && compgen -G "$candidate/lib/libX11.*" >/dev/null; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

echo "==> Checking prerequisites"

if ! xcode-select -p >/dev/null 2>&1; then
  echo "Xcode Command Line Tools are not installed."
  echo "Run: xcode-select --install"
  exit 1
fi

echo "==> Installing Homebrew dependencies"

"$BREW" install \
  autoconf automake libtool pkgconf gsed gawk coreutils \
  llvm cmake make \
  libffi openssl@3 libxml2 libxslt icu4c zlib bdw-gc gnutls \
  jpeg-turbo libpng libtiff fontconfig freetype \
  libicns portaudio

if ! X11_PREFIX="$(detect_x11_prefix)"; then
  if [[ -n "$REQUESTED_X11_PREFIX" ]]; then
    echo "No usable X11 installation found at X11_PREFIX=$REQUESTED_X11_PREFIX."
    exit 1
  fi

  echo "==> Installing XQuartz"
  "$BREW" install --cask xquartz
fi

if ! X11_PREFIX="$(detect_x11_prefix)"; then
  echo "No usable macOS X11 installation found."
  echo "Expected X11 headers and libraries under one of:"
  echo "  /opt/X11, /usr/X11, /usr/X11R6, /usr/local/X11"
  echo "Install XQuartz, or set X11_PREFIX to an existing X11 prefix."
  exit 1
fi

X11_PKG_CONFIG_PATH=""
if [[ -d "$X11_PREFIX/lib/pkgconfig" ]]; then
  X11_PKG_CONFIG_PATH="$X11_PREFIX/lib/pkgconfig"
fi

echo "==> Using X11 from $X11_PREFIX"

mkdir -p "$SRCROOT"
cd "$SRCROOT"

# clone_or_update REPO DIR TAG
#
# Clones the gnustep/REPO repository from GitHub into DIR if it does not
# already exist, then fetches all tags and checks out the specified TAG.
# Idempotent: subsequent calls simply update the working tree to TAG.
#
# Arguments:
#   REPO  GitHub repository name under the gnustep organisation (e.g. tools-make)
#   DIR   Local directory to clone into (relative to $SRCROOT)
#   TAG   Git tag or ref to check out (e.g. make-2_9_3)
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
clone_or_update libobjc2   libobjc2   "$LIBOBJC2_TAG"
clone_or_update libs-base  libs-base  "$LIBS_BASE_TAG"
clone_or_update libs-gui   libs-gui   "$LIBS_GUI_TAG"
clone_or_update libs-back  libs-back  "$LIBS_BACK_TAG"

# reset_patch_targets
#
# Reverts every source file that the patch_* functions may modify back to its
# committed upstream state using "git checkout --".  This guarantees a clean
# baseline before patches are (re-)applied so the script is safely re-entrant.
# Only files that are tracked by git in the respective repositories are touched;
# the function is a no-op for any repository directory that does not exist.
reset_patch_targets() {
  if [[ -d "$SRCROOT/tools-make/.git" ]]; then
    git -C "$SRCROOT/tools-make" checkout -- target.make
  fi

  if [[ -d "$SRCROOT/libobjc2/.git" ]]; then
    git -C "$SRCROOT/libobjc2" checkout -- CMakeLists.txt
  fi

  if [[ -d "$SRCROOT/libs-base/.git" ]]; then
    git -C "$SRCROOT/libs-base" checkout -- \
      Headers/Foundation/Foundation.h \
      Tools/HTMLLinker.m \
      Tools/autogsdoc.m \
      Tools/cvtenc.m \
      Tools/defaults.m \
      Tools/gdnc.m \
      Tools/gdomap.c \
      Tools/gspath.m \
      Tools/pl2link.m \
      Tools/pldes.m \
      Tools/plget.m \
      Tools/plmerge.m \
      Tools/plparse.m \
      Tools/plser.m \
      Tools/plutil.m \
      Tools/sfparse.m \
      Tools/xmlparse.m \
      Source/GSArray.m \
      Source/GSString.m \
      Source/NSArray.m \
      Source/GSDictionary.m \
      Source/NSDictionary.m \
      Source/NSPropertyList.m \
      Source/NSSerializer.m \
      Source/NSFileManager.m \
      Source/NSDatePrivate.h \
      Source/NSNumber.m \
      Source/NSNotificationCenter.m \
      Source/NSObject.m \
      Source/NSUserDefaults.m \
      Source/NSZone.m \
      Source/NSAutoreleasePool.m
  fi

  if [[ -d "$SRCROOT/libs-gui/.git" ]]; then
    git -C "$SRCROOT/libs-gui" checkout -- \
      Tools/GNUmakefile \
      Tools/gclose.m \
      Tools/gcloseall.m \
      Tools/gopen.m \
      Tools/make_services.m \
      Tools/set_show_service.m
  fi

  if [[ -d "$SRCROOT/libs-back/.git" ]]; then
    git -C "$SRCROOT/libs-back" checkout -- \
      Source/x11/scale.c \
      Source/x11/xutil.c \
      Tools/font_cacher.m \
      Tools/gpbs.m
  fi
}

patch_libobjc2_for_darwin_clang() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    return
  fi

  local cmake_lists="$SRCROOT/libobjc2/CMakeLists.txt"
  if [[ -f "$cmake_lists" ]]; then
    perl -0pi -e 's/-fobjc-runtime=gnustep-2\.0/-fobjc-runtime=gnustep-1.7/g' "$cmake_lists"
  fi
}

# patch_tools_make_for_darwin_gcc
#
# macOS-only.  Removes the "-Wl,-noall_load" linker flag from
# tools-make/target.make.  The flag is accepted by the Apple linker but is
# not understood by GNU ld / lld, and it causes spurious link errors when
# building with Homebrew GCC on macOS.  No-op on non-Darwin platforms.
patch_tools_make_for_darwin_gcc() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    return
  fi

  local target_make="$SRCROOT/tools-make/target.make"

  if [[ -f "$target_make" ]]; then
    perl -0pi -e 's/-Wl,-noall_load\s+//g' "$target_make"
  fi
}

# patch_libs_base_for_darwin_gcc
#
# macOS-only.  Tightens the preprocessor guard around the optional
# CoreFoundation and libdispatch includes inside Foundation.h so that those
# headers are skipped when building with the GNU Objective-C runtime
# (__GNU_LIBOBJC__ is defined).  Without this guard, GCC picks up Apple
# runtime declarations that are incompatible with libobjc-gnu.  No-op on
# non-Darwin platforms.
patch_libs_base_for_darwin_gcc() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    return
  fi

  local foundation_header="$SRCROOT/libs-base/Headers/Foundation/Foundation.h"

  if [[ -f "$foundation_header" ]]; then
    perl -0pi -e 's/#ifdef __has_include\n#  if __has_include\(<CoreFoundation\/CoreFoundation\.h>\)\n#    include <CoreFoundation\/CoreFoundation\.h>\n#  endif\n#  if __has_include\(<dispatch\/dispatch\.h>\)\n#    include <dispatch\/dispatch\.h>\n#  endif\n#endif/#if defined(__has_include) \&\& !defined(__GNU_LIBOBJC__)\n#  if __has_include(<CoreFoundation\/CoreFoundation.h>)\n#    include <CoreFoundation\/CoreFoundation.h>\n#  endif\n#  if __has_include(<dispatch\/dispatch.h>)\n#    include <dispatch\/dispatch.h>\n#  endif\n#endif/g' "$foundation_header"
  fi
}

# patch_gdomap_for_modern_sdk
#
# Fixes forward-declaration mismatches in gdomap.c that are rejected by
# compilers that apply strict prototype checking (e.g. GCC 15+ with
# -Wstrict-prototypes as an error).  Specifically:
#   - Adds an "int sig" parameter to the dump_tables() prototype and definition
#     to match its use as a signal handler.
#   - Updates the function-pointer type of ifun from "void (*)(void)" to
#     "void (*)(int)" for the same reason.
patch_gdomap_for_modern_sdk() {
  local gdomap="$SRCROOT/libs-base/Tools/gdomap.c"
  if [[ ! -f "$gdomap" ]]; then
    return
  fi

  perl -pi -e 's/^(static void\s+dump_tables)\(\);$/$1(int sig);/' "$gdomap"
  perl -pi -e 's/^(dump_tables)\(\)$/$1(int sig)/' "$gdomap"
  perl -pi -e 's/void\s+\(\*ifun\)\(\)/void (*ifun)(int)/' "$gdomap"
}

# patch_small_objects_for_gnu_runtime
#
# GNUstep small object representations require runtime support in
# object_getClass().  Homebrew GCC's GNU Objective-C runtime exposes small
# object capability macros, but its object_getClass() implementation still
# dereferences the object pointer directly.  Disable these representations for
# that runtime so autorelease pools do not try to release encoded pointer values
# as normal Objective-C objects.
patch_small_objects_for_gnu_runtime() {
  local number="$SRCROOT/libs-base/Source/NSNumber.m"
  local string="$SRCROOT/libs-base/Source/GSString.m"
  local date_private="$SRCROOT/libs-base/Source/NSDatePrivate.h"

  if [[ -f "$number" ]]; then
    perl -0pi -e 's/#ifdef OBJC_SMALL_OBJECT_SHIFT/#if defined(OBJC_SMALL_OBJECT_SHIFT) \&\& !defined(__GNU_LIBOBJC__)/g' "$number"
  fi

  if [[ -f "$string" ]]; then
    perl -0pi -e 's/#if defined\(OBJC_SMALL_OBJECT_SHIFT\) && \(OBJC_SMALL_OBJECT_SHIFT == 3\)/#if defined(OBJC_SMALL_OBJECT_SHIFT) \&\& (OBJC_SMALL_OBJECT_SHIFT == 3) \&\& !defined(__GNU_LIBOBJC__)/g' "$string"
  fi

  if [[ -f "$date_private" ]]; then
    perl -0pi -e 's/#if defined\(OBJC_SMALL_OBJECT_SHIFT\) && \(OBJC_SMALL_OBJECT_SHIFT == 3\)/#if defined(OBJC_SMALL_OBJECT_SHIFT) \&\& (OBJC_SMALL_OBJECT_SHIFT == 3) \&\& !defined(__GNU_LIBOBJC__)/' "$date_private"
  fi
}

patch_nsarray_cached_imp_for_darwin_gcc() {
  local array="$SRCROOT/libs-base/Source/NSArray.m"
  if [[ ! -f "$array" ]]; then
    return
  fi

  perl -0pi -e 's/IMP(\s+)get;/id (*get)(id, SEL, NSUInteger);/g' "$array"
  perl -0pi -e 's/IMP(\s+)get([01]?)(\s*=\s*\[[^\]]+\s+methodForSelector:\s*oaiSel\];)/id (*get$2)(id, SEL, NSUInteger)$3/g' "$array"
  perl -0pi -e 's/(\n\s+get\s*=\s*)\[(array|otherArray|self)\s+methodForSelector:\s*oaiSel\];/$1(id (*)(id, SEL, NSUInteger))[$2 methodForSelector: oaiSel];/g' "$array"
  perl -0pi -e 's/IMP(\s+)add(\s*=\s*\[self\s+methodForSelector:\s*addSel\];)/void (*add)(id, SEL, id)$2/g' "$array"
}

patch_gsarray_cached_imp_for_darwin_gcc() {
  local array="$SRCROOT/libs-base/Source/GSArray.m"
  if [[ ! -f "$array" ]]; then
    return
  fi

  perl -0pi -e 's/IMP(\s+)get1(\s*=\s*\[otherArray\s+methodForSelector:\s*oaiSel\];)/id (*get1)(id, SEL, NSUInteger)$2/g' "$array"
}

patch_gsdictionary_cached_imp_for_darwin_gcc() {
  local dict="$SRCROOT/libs-base/Source/GSDictionary.m"
  if [[ ! -f "$dict" ]]; then
    return
  fi

  perl -0pi -e 's|#define\s+GSI_MAP_HASH\(M, X\)\s+\[X\.obj hash\]\n#define\s+GSI_MAP_EQUAL\(M, X,Y\)\s+\[X\.obj isEqual: Y\.obj\]\n#define\s+GSI_MAP_RETAIN_KEY\(M, X\)\s+\(\(X\)\.obj\) = \\\n\s+\[\(\(id\)\(X\)\.obj\) copyWithZone: map->zone\]|#if defined(__APPLE__) \&\& defined(__GNU_LIBOBJC__)\nstatic inline NSUInteger\nGSDictionaryMapHash(id obj)\n{\n  static SEL hashSel = NULL;\n  if (hashSel == NULL)\n    hashSel = \@selector(hash);\n  return ((NSUInteger (*)(id, SEL))objc_msg_lookup(obj, hashSel))(obj, hashSel);\n}\n\nstatic inline BOOL\nGSDictionaryMapEqual(id obj, id other)\n{\n  static SEL equalSel = NULL;\n  if (equalSel == NULL)\n    equalSel = \@selector(isEqual:);\n  return ((BOOL (*)(id, SEL, id))objc_msg_lookup(obj, equalSel))(obj, equalSel, other);\n}\n\nstatic inline id\nGSDictionaryMapCopyWithZone(id obj, NSZone *zone)\n{\n  static SEL copySel = NULL;\n  if (copySel == NULL)\n    copySel = \@selector(copyWithZone:);\n  return ((id (*)(id, SEL, NSZone *))objc_msg_lookup(obj, copySel))(obj, copySel, zone);\n}\n\n#define\tGSI_MAP_HASH(M, X)\t\tGSDictionaryMapHash((X).obj)\n#define\tGSI_MAP_EQUAL(M, X,Y)\t\tGSDictionaryMapEqual((X).obj, (Y).obj)\n#define\tGSI_MAP_RETAIN_KEY(M, X)\t((X).obj) = \\\n\t\t\t\t\tGSDictionaryMapCopyWithZone((id)(X).obj, map->zone)\n#else\n#define\tGSI_MAP_HASH(M, X)\t\t[X.obj hash]\n#define\tGSI_MAP_EQUAL(M, X,Y)\t\t[X.obj isEqual: Y.obj]\n#define\tGSI_MAP_RETAIN_KEY(M, X)\t((X).obj) = \\\n\t\t\t\t\t[((id)(X).obj) copyWithZone: map->zone]\n#endif|g' "$dict"
  perl -0pi -e 's/IMP(\s+)nxtObj(\s*=\s*\[e\s+methodForSelector:\s*nxtSel\];)/id (*nxtObj)(id, SEL)$2/g' "$dict"
  perl -0pi -e 's/IMP(\s+)otherObj(\s*=\s*\[other\s+methodForSelector:\s*objSel\];)/id (*otherObj)(id, SEL, id)$2/g' "$dict"
}

patch_nsdictionary_cached_imp_for_darwin_gcc() {
  local dict="$SRCROOT/libs-base/Source/NSDictionary.m"
  if [[ ! -f "$dict" ]]; then
    return
  fi

  perl -0pi -e 's/IMP(\s+)(nxtObj|nxtImp)(\s*=\s*\[[^\]]+\s+methodForSelector:\s*nxtSel\];)/id (*$2)(id, SEL)$3/g' "$dict"
  perl -0pi -e 's/IMP(\s+)(myObj|otherObj|getObj|objImp)(\s*=\s*\[[^\]]+\s+methodForSelector:\s*objSel\];)/id (*$2)(id, SEL, id)$3/g' "$dict"
  perl -0pi -e 's/IMP(\s+)objectForKey(\s*=\s*\[self\s+methodForSelector:\s*objectForKeySelector\];)/id (*objectForKey)(id, SEL, id)$2/g' "$dict"
  perl -0pi -e 's/IMP(\s+)addObject(\s*=\s*\[buildSet\s+methodForSelector:\s*addObjectSelector\];)/void (*addObject)(id, SEL, id)$2/g' "$dict"
  perl -0pi -e 's/IMP(\s+)(remObj)(\s*=\s*\[self\s+methodForSelector:\s*remSel\];)/void (*$2)(id, SEL, id)$3/g' "$dict"
  perl -0pi -e 's/IMP(\s+)(setObj)(\s*=\s*\[self\s+methodForSelector:\s*setSel\];)/void (*$2)(id, SEL, id, id)$3/g' "$dict"
  perl -0pi -e 's/IMP(\s+)(setObj);/void (*$2)(id, SEL, id, id);/g' "$dict"
}

patch_nsuserdefaults_cached_imp_for_darwin_gcc() {
  local defaults="$SRCROOT/libs-base/Source/NSUserDefaults.m"
  if [[ ! -f "$defaults" ]]; then
    return
  fi

  perl -0pi -e 's/IMP(\s+)(pImp|tImp);/id (*$2)(id, SEL, id);/g' "$defaults"
  perl -0pi -e 's/IMP(\s+)nImp;/id (*nImp)(id, SEL);/g' "$defaults"
  perl -0pi -e 's/IMP(\s+)addImp;/void (*addImp)(id, SEL, id);/g' "$defaults"
  perl -0pi -e 's/(\n\s+[pt]Imp\s*=\s*)\[(_persDomains|_tempDomains)\s+methodForSelector:\s*objectForKeySel\];/$1(id (*)(id, SEL, id))[$2 methodForSelector: objectForKeySel];/g' "$defaults"
  perl -0pi -e 's/(\n\s+nImp\s*=\s*)\[enumerator\s+methodForSelector:\s*nextObjectSel\];/$1(id (*)(id, SEL))[enumerator methodForSelector: nextObjectSel];/g' "$defaults"
  perl -0pi -e 's/(\n\s+addImp\s*=\s*)\[dictRep\s+methodForSelector:\s*addSel\];/$1(void (*)(id, SEL, id))[dictRep methodForSelector: addSel];/g' "$defaults"
}

patch_nsfilemanager_cached_imp_for_darwin_gcc() {
  local filemanager="$SRCROOT/libs-base/Source/NSFileManager.m"
  if [[ ! -f "$filemanager" ]]; then
    return
  fi

  perl -0pi -e 's/IMP(\s+)nxtImp;/id (*nxtImp)(id, SEL);/g' "$filemanager"
  perl -0pi -e 's/IMP(\s+)addImp;/void (*addImp)(id, SEL, id);/g' "$filemanager"
  perl -0pi -e 's/(\n\s+nxtImp\s*=\s*)\[direnum\s+methodForSelector:\s*@selector\(nextObject\)\];/$1(id (*)(id, SEL))[direnum methodForSelector: @selector(nextObject)];/g' "$filemanager"
  perl -0pi -e 's/(\n\s+addImp\s*=\s*)\[content\s+methodForSelector:\s*@selector\(addObject:\)\];/$1(void (*)(id, SEL, id))[content methodForSelector: @selector(addObject:)];/g' "$filemanager"
  perl -0pi -e 's/\n\s+id \(\*nxtImp\)\(id, SEL\);\n\s+void \(\*addImp\)\(id, SEL, id\);\n\s*\n\s+nxtImp = \[direnum methodForSelector: @selector\(nextObject\)\];\n\s+addImp = \[content methodForSelector: @selector\(addObject:\)\];\n\s*\n\s+while \(\(path = \(\*nxtImp\)\(direnum, @selector\(nextObject\)\)\) != nil\)\n\s+\{\n\s+\(\*addImp\)\(content, @selector\(addObject:\), path\);\n\s+\}/\n      while ((path = [direnum nextObject]) != nil)\n\t{\n\t  [content addObject: path];\n\t}/g' "$filemanager"
  perl -0pi -e 's/\n\s+id \(\*nxtImp\)\(id, SEL\);\n(\s+NSMutableArray\s+\*urlArray;\n\s+NSString\s+\*tempPath;\n\s*\n)\s+nxtImp = \[direnum methodForSelector: @selector\(nextObject\)\];\n\s*\n(\s+urlArray = \[NSMutableArray arrayWithCapacity: 128\];\n)\s+while \(\(tempPath = \(\*nxtImp\)\(direnum, @selector\(nextObject\)\)\) != nil\)/\n$1$2      while ((tempPath = [direnum nextObject]) != nil)/g' "$filemanager"
}

patch_nspropertylist_cached_imp_for_darwin_gcc() {
  local plist="$SRCROOT/libs-base/Source/NSPropertyList.m"
  if [[ ! -f "$plist" ]]; then
    return
  fi

  perl -0pi -e 's/IMP(\s+)myObj(\s*=\s*\[obj\s+methodForSelector:\s*objSel\];)/id (*myObj)(id, SEL, id)$2/g' "$plist"
}

patch_nsserializer_cached_imp_for_darwin_gcc() {
  local serializer="$SRCROOT/libs-base/Source/NSSerializer.m"
  if [[ ! -f "$serializer" ]]; then
    return
  fi

  perl -0pi -e 's/IMP(\s+)nxtImp;/id (*nxtImp)(id, SEL);/g' "$serializer"
  perl -0pi -e 's/IMP(\s+)objImp;/id (*objImp)(id, SEL, id);/g' "$serializer"
  perl -0pi -e 's/static IMP dInitImp;/static id (*dInitImp)(id, SEL, void *, NSUInteger);/g' "$serializer"
  perl -0pi -e 's/static IMP maInitImp;/static id (*maInitImp)(id, SEL, NSUInteger);/g' "$serializer"
  perl -0pi -e 's/static IMP mdInitImp;/static id (*mdInitImp)(id, SEL, NSUInteger);/g' "$serializer"
  perl -0pi -e 's/static IMP maAddImp;/static void (*maAddImp)(id, SEL, id);/g' "$serializer"
  perl -0pi -e 's/static IMP mdSetImp;/static void (*mdSetImp)(id, SEL, id, id);/g' "$serializer"
}

# patch_nsobject_for_gnu_runtime
#
# Wraps GNU-Objective-C-2 runtime API calls inside NSObject.m with
# "#ifndef __GNU_LIBOBJC__" / "#endif" guards so that the code compiles
# correctly when linked against Homebrew GCC's libobjc-gnu (which defines
# __GNU_LIBOBJC__ but does not export the ARC weak-ref or block-class
# functions from the Apple/libobjc2 ABI).  Affected symbols:
#   - objc_create_block_classes_as_subclasses_of
#   - GSWeakInit
#   - objc_delete_weak_refs
# It also casts NSObject's cached autorelease IMP to a fixed-argument
# function pointer before calling it.  On Darwin arm64, calling GCC's
# variadic IMP type directly passes the object argument incorrectly.
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
  if rg -q '\(\*autorelease_imp\)\(autorelease_class, autorelease_sel, self\);' "$nsobject"; then
    perl -0pi -e 's|\(\*autorelease_imp\)\(autorelease_class, autorelease_sel, self\);|#if defined(__APPLE__) \&\& defined(__GNU_LIBOBJC__)\n  ((void (*)(id, SEL, id))autorelease_imp)(autorelease_class, autorelease_sel, self);\n#else\n  (*autorelease_imp)(autorelease_class, autorelease_sel, self);\n#endif|' "$nsobject"
  fi
}

# patch_nsnotificationcenter_for_gnu_runtime
#
# Abstracts the weak-reference operations used for notification observers in
# NSNotificationCenter.m behind a set of GSNotificationObserver* inline
# helpers.  The helpers have two implementations selected at compile time:
#   - __GNU_LIBOBJC__ branch: plain pointer assignment / nil (no weak ARC).
#   - Default branch: objc_initWeak / objc_loadWeak / objc_destroyWeak.
# All direct call sites of the objc_*Weak family are then rewritten to use
# the abstract helpers, making the file compile cleanly under both runtimes.
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

# patch_nszone_for_darwin_gcc
#
# Applies three fixes to NSZone.m that are required when building with GCC on
# macOS:
#   1. Replaces the Objective-C string literal @"default" in the static
#      default_zone initialiser with 0, because GCC cannot use ObjC literals in
#      static storage.  A constructor function init_default_zone_name() is
#      injected to set the name field at startup instead.
#   2. Injects the init_default_zone_name() constructor if it is not already
#      present.
#   3. Fast-paths NSZoneMalloc() to call default_malloc() directly when the
#      zone is nil or is the default zone, avoiding a redundant pointer chase.
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

# patch_nsautoreleasepool_for_gnu_runtime
#
# Applies several fixes to NSAutoreleasePool.m for the GNU ObjC runtime on
# macOS:
#   1. Injects a GSAutoreleasePointerLooksValid() helper (Apple + __GNU_LIBOBJC__
#      only) that sanity-checks a pointer's bit pattern before dereferencing it.
#      This catches wild pointers that would otherwise hard-crash during pool
#      drainage.
#   2. Drops invalid pointers before they are inserted into the autorelease
#      list, then sanity-checks both the object pointer
#      and its class pointer in the drain loop, guarded by the same #if block.
#   3. Replaces NSAllocateObject(self, 0, zone) with
#      NSAllocateObject(self, 0, NULL) to avoid passing a potentially stale zone.
#   4. Replaces the overengineered cached-IMP implementation of +new with a
#      simple [[self allocWithZone: NULL] init] one-liner.
#   5. Avoids the cached _addImp path in +addObject: for this runtime; GCC's
#      runtime can resolve the cached IMP to the class method, which causes the
#      function address itself to be inserted into the autorelease list.  A
#      direct C helper is used instead of another Objective-C message send.
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

  if ! rg -q 'invalid object ignored by autorelease pool' "$arp"; then
    perl -0pi -e 's|  if \(!autorelease_enabled\)\n    return;\n|  if (!autorelease_enabled)\n    return;\n\n#if defined(__APPLE__) && defined(__GNU_LIBOBJC__)\n  if (NO == GSAutoreleasePointerLooksValid(anObj))\n    {\n      fprintf(stderr,\n        "invalid object ignored by autorelease pool: %p\\n", anObj);\n      return;\n    }\n#endif\n|s' "$arp"
  fi

  if ! rg -q 'GSAutoreleasePoolAddObjectDirect' "$arp"; then
    perl -0pi -e 's|(\nstatic id\npop_pool_from_cache\(struct autorelease_thread_vars \*tv\)\n\{\n  return tv->pool_cache\[--\(tv->pool_cache_count\)\];\n\}\n)|$1\n#if defined(__APPLE__) \&\& defined(__GNU_LIBOBJC__)\nstatic inline void\nGSAutoreleasePoolAddObjectDirect(NSAutoreleasePool *pool, id anObj)\n{\n  if (!autorelease_enabled)\n    {\n      return;\n    }\n  if (NO == GSAutoreleasePointerLooksValid(anObj))\n    {\n      fprintf(stderr,\n        "invalid object ignored by autorelease pool: %p\\n", anObj);\n      return;\n    }\n  if (pool->_released_count >= pool_count_warning_threshold)\n    {\n      [NSException raise: NSGenericException\n                  format: @"AutoreleasePool count threshold exceeded."];\n    }\n  while (pool->_released->count == pool->_released->size)\n    {\n      if (pool->_released->next)\n        {\n          pool->_released = pool->_released->next;\n        }\n      else\n        {\n          struct autorelease_array_list *new_released;\n          unsigned new_size = pool->_released->size * 2;\n\n          new_released = (struct autorelease_array_list*)\n            NSZoneMalloc(NSDefaultMallocZone(),\n              sizeof(struct autorelease_array_list) + (new_size * sizeof(id)));\n          new_released->next = NULL;\n          new_released->size = new_size;\n          new_released->count = 0;\n          pool->_released->next = new_released;\n          pool->_released = new_released;\n        }\n    }\n  pool->_released->objects[pool->_released->count] = anObj;\n  (pool->_released->count)++;\n  pool->_released_count++;\n}\n#endif\n|s' "$arp"
  fi

  perl -pi -e 's|^(\s*)\(\*pool->_addImp\).*anObj\);|${1}#if defined(__APPLE__) \&\& defined(__GNU_LIBOBJC__)\n${1}[pool addObject: anObj];\n${1}#else\n${1}(*pool->_addImp)(pool, \@selector(addObject:), anObj);\n${1}#endif|' "$arp"
  perl -pi -e 's/\[pool addObject: anObj\];/GSAutoreleasePoolAddObjectDirect(pool, anObj);/g' "$arp"

  perl -pi -e 's/NSAllocateObject \(self, 0, zone\)/NSAllocateObject (self, 0, NULL)/g' "$arp"

  if rg -q '^\+ \(id\) new$' "$arp"; then
    perl -0pi -e 's|\+ \(id\) new\n\{\n  static IMP\s+allocImp = 0;\n  static IMP\s+initImp = 0;\n  id\s+arp;\n\n  if \(0 == allocImp\)\n    \{\n      allocImp\n\s*= \[NSAutoreleasePool methodForSelector: \@selector\(allocWithZone:\)\];\n      initImp\n\s*= \[NSAutoreleasePool instanceMethodForSelector: \@selector\(init\)\];\n    \}\n  arp = \(\*allocImp\)\(self, \@selector\(allocWithZone:\), NSDefaultMallocZone\(\)\);\n  return \(\*initImp\)\(arp, \@selector\(init\)\);\n\}|+ (id) new\n{\n  return [[self allocWithZone: NULL] init];\n}|s' "$arp"
  fi
}

# patch_nsautoreleasepool_runtime_safety
#
# Refines the GSAutoreleasePointerLooksValid guard blocks that were inserted by
# patch_nsautoreleasepool_for_gnu_runtime.  The initial insertion zeroes all
# remaining pool lists and breaks, which is overly aggressive.  This patch
# replaces those blocks with a plain break so that only the current
# autorelease_array_list's iteration is stopped.  The outer loop continues to
# the next (valid) array_list, and the existing "released->count = 0" statement
# that follows the inner loop cleans up the current list.
#
# Using break (rather than continue, which was tried earlier) is critical:
# if the pool's count field is garbage (e.g. because Apple ObjC runtime objects
# contaminated the pool's backing memory), continue would iterate through the
# entire garbage range, making thousands of out-of-bounds reads and ultimately
# following a corrupt ->next pointer into a segfault.  break exits immediately.
patch_nsautoreleasepool_runtime_safety() {
  local arp="$SRCROOT/libs-base/Source/NSAutoreleasePool.m"
  if [[ ! -f "$arp" ]]; then
    return
  fi

  perl -0pi -e 's|#if defined\(__APPLE__\) && defined\(__GNU_LIBOBJC__\)\n\s*if \(NO == GSAutoreleasePointerLooksValid\(anObject\)\)\n\s*\{\n\s*volatile struct autorelease_array_list \*remaining = released;\n\n\s*fprintf\(stderr,\n\s*"invalid object encountered in autorelease pool: %p\\n",\n\s*anObject\);\n\s*while \(remaining != 0\)\n\s*\{\n\s*remaining->count = 0;\n\s*remaining = remaining->next;\n\s*\}\n\s*_released_count = 0;\n\s*break;\n\s*\}\n\s*#endif|#if defined(__APPLE__) && defined(__GNU_LIBOBJC__)\n      if (NO == GSAutoreleasePointerLooksValid(anObject))\n        {\n          fprintf(stderr,\n            "invalid object encountered in autorelease pool: %p\\n",\n            anObject);\n          break;\n        }\n      #endif|s; s|#if defined\(__APPLE__\) && defined\(__GNU_LIBOBJC__\)\n\s*if \(NO == GSAutoreleasePointerLooksValid\(c\)\)\n\s*\{\n\s*volatile struct autorelease_array_list \*remaining = released;\n\n\s*fprintf\(stderr,\n\s*"invalid class encountered in autorelease pool: object=%p class=%p\\n",\n\s*anObject, c\);\n\s*while \(remaining != 0\)\n\s*\{\n\s*remaining->count = 0;\n\s*remaining = remaining->next;\n\s*\}\n\s*_released_count = 0;\n\s*break;\n\s*\}\n\s*#endif|#if defined(__APPLE__) && defined(__GNU_LIBOBJC__)\n      if (NO == GSAutoreleasePointerLooksValid(c))\n        {\n          fprintf(stderr,\n            "invalid class encountered in autorelease pool: object=%p class=%p\\n",\n            anObject, c);\n          break;\n        }\n      #endif|s' "$arp"
}

# patch_tool_processinfo_init_guards
#
# Removes "#ifdef GS_PASS_ARGUMENTS" preprocessor guards that wrap process
# initialization in GNUstep command-line tools.  On Darwin with the GNU
# Objective-C runtime, helper tools built during bootstrap must always publish
# argc/argv/env to GNUstep before using Foundation.  Otherwise tools such as
# plmerge fail while backend bundles are being installed.
#
# Operates on every .m file under Tools/ in the three library source trees that
# still contains the guard, as reported by ripgrep.
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
      perl -0pi -e 's|#ifdef GS_PASS_ARGUMENTS\n([ \t]*GSInitializeProcess\([^\n]*\);)\n[ \t]*#endif|$1|g' "$file"
    done < <(rg -l '#ifdef GS_PASS_ARGUMENTS' "$root")
  done
}

# patch_libs_back_x11_for_modern_gcc
#
# GCC 15 treats empty function parameter lists as strict prototypes in places
# that older C tolerated.  The X11 backend has two old declarations that then
# fail to compile:
#   - oldErrorHandler must use Xlib's XErrorHandler signature.
#   - filterf must accept the double argument passed by the scaler.
patch_libs_back_x11_for_modern_gcc() {
  local xutil="$SRCROOT/libs-back/Source/x11/xutil.c"
  local scale="$SRCROOT/libs-back/Source/x11/scale.c"

  if [[ -f "$xutil" ]]; then
    perl -pi -e 's/static int \(\*oldErrorHandler\)\(\);/static XErrorHandler oldErrorHandler;/' "$xutil"
  fi

  if [[ -f "$scale" ]]; then
    perl -pi -e 's/static double \(\*filterf\)\(\) = Mitchell_filter;/static double (*filterf)(double) = Mitchell_filter;/' "$scale"
  fi
}

reset_patch_targets
patch_gdomap_for_modern_sdk
patch_tool_processinfo_init_guards
patch_libs_back_x11_for_modern_gcc

# Common compiler and linker environment: Homebrew clang + libobjc2.
LLVM_PREFIX="$("$BREW" --prefix llvm)"
LIBOBJC2_PREFIX="${LIBOBJC2_PREFIX:-$PREFIX/Runtime/libobjc2}"

CLANG_CC="$LLVM_PREFIX/bin/clang"
CLANG_CXX="$LLVM_PREFIX/bin/clang++"
if [[ ! -x "$CLANG_CC" || ! -x "$CLANG_CXX" ]]; then
  echo "Homebrew clang not found under $LLVM_PREFIX/bin"
  echo "Try: $BREW install llvm"
  exit 1
fi

LIBOBJC2_INCLUDE_DIR="$LIBOBJC2_PREFIX/include"
LIBOBJC2_LIB_DIR="$LIBOBJC2_PREFIX/lib"

export CC="$CLANG_CC"
export CXX="$CLANG_CXX"
export OBJC="$CLANG_CC"
export OBJCXX="$CLANG_CXX"
OBJC_RUNTIME_LIB_FLAG="-lobjc"

echo "==> Using clang from $LLVM_PREFIX"
echo "==> Installing libobjc2 into $LIBOBJC2_PREFIX"

export PKG_CONFIG="$BREW_PREFIX/bin/pkg-config"
export PKG_CONFIG_PATH="$LIBOBJC2_LIB_DIR/pkgconfig:${X11_PKG_CONFIG_PATH:+$X11_PKG_CONFIG_PATH:}$BREW_PREFIX/opt/icu4c/lib/pkgconfig:$BREW_PREFIX/opt/libxml2/lib/pkgconfig:$BREW_PREFIX/opt/libffi/lib/pkgconfig:$BREW_PREFIX/lib/pkgconfig${EXTRA_PKG_CONFIG_PATH:+:$EXTRA_PKG_CONFIG_PATH}"
export ACLOCAL_PATH="$BREW_PREFIX/share/aclocal${EXTRA_ACLOCAL_PATH:+:$EXTRA_ACLOCAL_PATH}"

# Bootstrap with Homebrew and the system X11 tree only. Keep X11 before
# Homebrew so the backend uses the macOS X11 installation even if Homebrew xorg
# libraries are present indirectly.
export CPPFLAGS="-I$LIBOBJC2_INCLUDE_DIR -I$X11_PREFIX/include -I$BREW_PREFIX/include -I$BREW_PREFIX/opt/icu4c/include -I$BREW_PREFIX/opt/libxml2/include -I$BREW_PREFIX/opt/libffi/include${EXTRA_CPPFLAGS:+ $EXTRA_CPPFLAGS}"
export LDFLAGS="-Wl,-rpath,$LIBOBJC2_LIB_DIR -L$LIBOBJC2_LIB_DIR -L$X11_PREFIX/lib -L$BREW_PREFIX/lib -L$BREW_PREFIX/opt/icu4c/lib -L$BREW_PREFIX/opt/libxml2/lib -L$BREW_PREFIX/opt/libffi/lib${EXTRA_LDFLAGS:+ $EXTRA_LDFLAGS}"

# Helpful runtime path for bootstrap tools built during the process.
export DYLD_LIBRARY_PATH="$LIBOBJC2_LIB_DIR:$X11_PREFIX/lib:$BREW_PREFIX/lib${EXTRA_DYLD_LIBRARY_PATH:+:$EXTRA_DYLD_LIBRARY_PATH}"
export LIBRARY_PATH="$LIBOBJC2_LIB_DIR:$X11_PREFIX/lib:$BREW_PREFIX/lib${EXTRA_LIBRARY_PATH:+:$EXTRA_LIBRARY_PATH}"
export CPATH="$LIBOBJC2_INCLUDE_DIR:$X11_PREFIX/include:$BREW_PREFIX/include${EXTRA_CPATH:+:$EXTRA_CPATH}"

export CFLAGS="${EXTRA_CFLAGS:-}"
export OBJCFLAGS="-fobjc-runtime=gnustep-1.7 -fblocks${EXTRA_OBJCFLAGS:+ $EXTRA_OBJCFLAGS}"

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

# reset_bootstrap_env
#
# Restores all compiler and linker environment variables (CC, CXX, OBJC,
# OBJCXX, CPPFLAGS, CFLAGS, OBJCFLAGS, LDFLAGS, PKG_CONFIG, PKG_CONFIG_PATH,
# ACLOCAL_PATH, DYLD_LIBRARY_PATH, LIBRARY_PATH, CPATH) to the baseline
# bootstrap values that were captured before any library build began.  This
# prevents environment pollution from one build stage leaking into the next.
# Also calls apply_preferred_compiler_env to re-pin the compiler to Homebrew
# GCC on macOS.
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

# run_as_root COMMAND [ARGS...]
#
# Executes COMMAND with root privileges via sudo.  If the environment variable
# SUDO_ASKPASS is set, sudo is invoked with the -A flag so that the configured
# askpass helper is used to prompt for the password (useful in GUI or headless
# environments).  Otherwise sudo is invoked normally, which prompts on the
# terminal.
#
# Arguments:
#   COMMAND  The command to run as root.
#   ARGS     Any additional arguments forwarded verbatim to COMMAND.
run_as_root() {
  if [[ "${GNUSTEP_BUILD_USE_SUDO:-auto}" == "no" ]]; then
    "$@"
    return
  fi

  if [[ -n "${SUDO_ASKPASS:-}" ]]; then
    sudo -A "$@"
  else
    sudo "$@"
  fi
}

# build_libobjc2
#
# Builds the GNUstep Objective-C runtime from source with Homebrew clang and
# installs it into LIBOBJC2_PREFIX.  Homebrew's libobjc2 formula is not
# available on all macOS configurations, so this script treats libobjc2 as a
# source dependency alongside the other GNUstep repositories.
build_libobjc2() {
  echo "==> Building libobjc2"
  cd "$SRCROOT/libobjc2"

  patch_libobjc2_for_darwin_clang
  rm -rf build
  cmake -S . -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$LIBOBJC2_PREFIX" \
    -DCMAKE_INSTALL_RPATH="$LIBOBJC2_LIB_DIR" \
    -DCMAKE_C_COMPILER="$CLANG_CC" \
    -DCMAKE_CXX_COMPILER="$CLANG_CXX" \
    -DCMAKE_OBJC_COMPILER="$CLANG_CC" \
    -DCMAKE_OBJCXX_COMPILER="$CLANG_CXX" \
    -DCMAKE_OBJC_FLAGS="$OBJCFLAGS" \
    -DCMAKE_OBJCXX_FLAGS="$OBJCFLAGS" \
    -DCMAKE_PREFIX_PATH="$BREW_PREFIX;$LLVM_PREFIX" \
    -DLIBOBJC_NAME=objc \
    -DEMBEDDED_BLOCKS_RUNTIME=ON \
    -DTESTS=OFF
  cmake --build build -j"$JOBS"
  run_as_root cmake --install build

  if [[ ! -f "$LIBOBJC2_INCLUDE_DIR/objc/runtime.h" || ! -f "$LIBOBJC2_LIB_DIR/libobjc.dylib" ]]; then
    echo "libobjc2 install did not produce expected headers and dylib."
    echo "Expected:"
    echo "  $LIBOBJC2_INCLUDE_DIR/objc/runtime.h"
    echo "  $LIBOBJC2_LIB_DIR/libobjc.dylib"
    exit 1
  fi
}

# ensure_prefix_permissions
#
# Sets safe, predictable filesystem permissions on the GNUstep prefix tree so
# that build tools can read headers and libraries without additional privilege
# escalation.  Specifically:
#   - Chmod 755 on each top-level GNUstep directory under $PREFIX (System,
#     Local, and their Library subdirectories) if they exist.
#   - Recursively chmod 755 on all directories and 644 on all regular files
#     under the Headers and Libraries subtrees.
# All operations that require root are delegated to run_as_root.
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

# purge_installed_libobjc2
#
# Removes any libobjc2 headers and libraries that may have been installed into
# $PREFIX from a previous build.  This is necessary because the current build
# uses Homebrew GCC's own libobjc-gnu rather than libobjc2, and stale libobjc2
# artifacts in $PREFIX can shadow the correct runtime and cause link or runtime
# failures.  Only paths that actually exist are removed; the function is a
# no-op if the prefix is clean.  Deletion is performed via run_as_root.
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
  "--with-config-file=$PREFIX/etc/GNUstep/GNUstep.conf"
  "--disable-strip"
)

if [[ "$(uname -s)" == "Darwin" ]]; then
  MAKE_CONFIGURE_FLAGS+=(
    "--with-library-combo=gnu-gnu-gnu"
    "--with-objc-lib-flag=$OBJC_RUNTIME_LIB_FLAG"
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

# apply_preferred_compiler_env
#
# Re-exports the CC, CXX, OBJC, and OBJCXX variables to point at Homebrew
# clang.  This is called after sourcing GNUstep.sh, which may reset compiler
# variables on macOS.
apply_preferred_compiler_env() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    export CC="$CLANG_CC"
    export CXX="$CLANG_CXX"
    export OBJC="$CLANG_CC"
    export OBJCXX="$CLANG_CXX"
  fi
}

# source_gnustep_env
#
# Sources the GNUstep environment script ($PREFIX/System/Library/Makefiles/
# GNUstep.sh) which sets up GNUSTEP_MAKEFILES, GNUSTEP_USER_DEFAULTS_DIR, and
# other GNUstep variables required by the build system.  GNUstep.sh references
# unset variables, so the bash "nounset" option (-u) is temporarily disabled
# for the duration of the source operation and restored afterwards.
# apply_preferred_compiler_env is called immediately after to ensure the
# compiler remains pinned to Homebrew clang.
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

# check_objc_compiler
#
# Verifies that the selected Objective-C compiler and libobjc2 runtime are
# functional before attempting any library build.  A minimal Objective-C
# translation unit that includes <objc/Object.h> is written to a temporary
# file, compiled with OBJCFLAGS and the runtime link flag, and executed.
# Any compilation or execution failure is reported with diagnostic output
# (compiler invocation, flag values, and the last 50 lines of the build log)
# before the script exits with a non-zero status.  Temporary files are always
# cleaned up.
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

  if ! "$OBJC" $OBJCFLAGS $CPPFLAGS "$probe_src" "$OBJC_RUNTIME_LIB_FLAG" $LDFLAGS -o "$probe_bin" >/tmp/gnustep-objc-probe.log 2>&1; then
    echo "Objective-C compile/link test failed with compiler: $OBJC"
    echo "OBJCFLAGS: ${OBJCFLAGS:-}"
    echo "CPPFLAGS:  ${CPPFLAGS:-}"
    echo "OBJCLIB: $OBJC_RUNTIME_LIB_FLAG"
    tail -n 50 /tmp/gnustep-objc-probe.log || true
    rm -f "$probe_src" "$probe_bin"
    exit 1
  fi

  # Verify the linked binary does not reference Apple's libobjc.dylib. If it
  # does, the wrong ObjC runtime was pulled in.
  if otool -L "$probe_bin" 2>/dev/null | grep -q '/usr/lib/libobjc\.'; then
    echo "ERROR: probe binary links against Apple's libobjc — wrong runtime."
    echo "Linked libraries:"
    otool -L "$probe_bin" || true
    echo "LIBOBJC2_LIB_DIR: ${LIBOBJC2_LIB_DIR:-}"
    echo "LDFLAGS: ${LDFLAGS:-}"
    rm -f "$probe_src" "$probe_bin"
    exit 1
  fi

  if ! otool -L "$probe_bin" 2>/dev/null | grep -q "$LIBOBJC2_LIB_DIR/libobjc"; then
    echo "ERROR: probe binary did not link against Homebrew libobjc2."
    echo "Linked libraries:"
    otool -L "$probe_bin" || true
    echo "LIBOBJC2_LIB_DIR: ${LIBOBJC2_LIB_DIR:-}"
    echo "LDFLAGS: ${LDFLAGS:-}"
    rm -f "$probe_src" "$probe_bin"
    exit 1
  fi

  if ! "$probe_bin" >/dev/null 2>&1; then
    echo "Objective-C runtime execution test failed."
    echo "DYLD_LIBRARY_PATH: ${DYLD_LIBRARY_PATH:-}"
    echo "Linked libraries:"
    otool -L "$probe_bin" 2>/dev/null || true
    rm -f "$probe_src" "$probe_bin"
    exit 1
  fi

  rm -f "$probe_src" "$probe_bin"
}

check_clang_gnustep_codegen() {
  if [[ "$(uname -s)" != "Darwin" || "${GNUSTEP_ALLOW_UNSUPPORTED_CLANG_LIBOBJC2:-no}" == "yes" ]]; then
    return
  fi

  echo "==> Checking clang GNUstep Objective-C code generation"

  local probe_src="/tmp/gnustep-clang-codegen-check.m"
  local probe_asm="/tmp/gnustep-clang-codegen-check.s"
  local probe_log="/tmp/gnustep-clang-codegen-check.log"

  cat > "$probe_src" <<'EOF'
@interface GNUstepCodegenProbe
- (id)copy;
@end
void probe(GNUstepCodegenProbe *object) { [object copy]; }
EOF

  if ! "$OBJC" $OBJCFLAGS -S "$probe_src" -o "$probe_asm" >"$probe_log" 2>&1; then
    echo "ERROR: clang cannot emit GNUstep Objective-C runtime code for this macOS target."
    echo
    echo "The selected compiler is:"
    echo "  $OBJC"
    echo
    echo "The failing flags are:"
    echo "  $OBJCFLAGS"
    echo
    echo "This is the same Mach-O backend limitation that prevents libobjc2 from"
    echo "building here. Current Apple/Homebrew clang rejects GNUstep runtime ABI 2.x"
    echo "on Darwin, and even the legacy GNUstep ABI path fails when lowering selector"
    echo "sections for Mach-O."
    echo
    echo "Last compiler output:"
    tail -n 20 "$probe_log" || true
    echo
    echo "Set GNUSTEP_ALLOW_UNSUPPORTED_CLANG_LIBOBJC2=yes to attempt the build anyway."
    rm -f "$probe_src" "$probe_asm"
    exit 1
  fi

  rm -f "$probe_src" "$probe_asm" "$probe_log"
}

# build_tools_make
#
# Configures, builds, and installs the GNUstep tools-make package into
# $PREFIX.  The steps are:
#   1. Run "make distclean" to remove any previous build artefacts.
#   2. Reset the environment to the bootstrap baseline (reset_bootstrap_env).
#   3. Run ./configure with MAKE_CONFIGURE_FLAGS.
#   4. Build and install to the SYSTEM domain with debug symbols.
#   5. On macOS, patch the installed target.make to strip -Wl,-noall_load.
#   6. Source the freshly installed GNUstep.sh to export GNUSTEP_MAKEFILES
#      and related variables for subsequent build steps.
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

# build_lib NAME [CONFIGURE_ARGS...]
#
# Configures, builds, and installs a GNUstep library (libs-base, libs-gui, or
# libs-back) into $PREFIX under the SYSTEM installation domain.  The steps are:
#   1. Change into $SRCROOT/NAME.
#   2. Run "make distclean" to start clean.
#   3. Source GNUstep.sh so the build system can locate tools-make.
#   4. Reset the environment to the bootstrap baseline and prepend
#      $PREFIX/System/Library/{Headers,Libraries} to the search paths so the
#      library can find previously installed GNUstep components.
#   5. Append library-specific configure flags (e.g. --disable-libdispatch for
#      libs-base) to any CONFIGURE_ARGS passed by the caller.
#   6. Run ./configure, then build and install with debug symbols.
#
# Arguments:
#   NAME            Repository/directory name (e.g. libs-base).
#   CONFIGURE_ARGS  Optional extra arguments forwarded to ./configure.
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
    extra_args+=("--enable-pass-arguments=yes")
  fi

  ./configure "${LIB_CONFIGURE_FLAGS[@]}" "${extra_args[@]}"
  make -j"$JOBS" GNUSTEP_INSTALLATION_DOMAIN=SYSTEM debug=yes
  run_as_root make GNUSTEP_INSTALLATION_DOMAIN=SYSTEM debug=yes install
  ensure_prefix_permissions
}

check_clang_gnustep_codegen
build_libobjc2
check_objc_compiler
build_tools_make


# Base first after make.
build_lib libs-base

# GUI next.
build_lib libs-gui \
  "--with-tiff-library=$BREW_PREFIX/lib"

# Back last; force the X11 server and xlib graphics path against the macOS X11
# installation discovered above.
build_lib libs-back \
  "--with-tiff-library=$BREW_PREFIX/lib" \
  "--enable-server=x11" \
  "--enable-graphics=xlib" \
  "--x-includes=$X11_PREFIX/include" \
  "--x-libraries=$X11_PREFIX/lib"

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
