# Maintainer: Some One <some.one@some.email.com>

_realname=libobjc2
pkgbase=mingw-w64-${_realname}
pkgname=("${MINGW_PACKAGE_PREFIX}-${_realname}")
pkgver=1314.ab25470
pkgrel=1
pkgdesc="GNUstep modern objc runtime (mingw-w64)"
arch=('x86_64')
url='https://www.github.com/gnustep/libobjc2/'
license=('LICENSE')
#validpgpkeys=('gpg_KEY')
makedepends=("${MINGW_PACKAGE_PREFIX}-cmake"
             'git')
options=('!strip' 'staticlibs' '!debug')

#source=("${_realname}"::"git+https://gitlab+deploy-token-19:zNYh5wak2zY3RHxQ8npU@git.testplant.com/EPF/libobjc2.git#branch=1.9clang7")
#source=("${_realname}"::"git+https://github.com/gnustep/libobjc2.git#branch=mingw")
#source=("${_realname}"::"git+https://github.com/TestPlant/libobjc2.git#branch=mingw")
#source=("${_realname}"::"git+https://github.com/gnustep/libobjc2.git#branch=mingw_fixes")
#source=("${_realname}"::"git+https://github.com/gnustep/libobjc2.git#branch=master")
#source=("${_realname}"::"git+https://github.com/gnustep/libobjc2.git#branch=msys2_updates")
#source=("${_realname}"::"git+https://github.com/Microsoft/libobjc2")

sha256sums=('SKIP')
tests_enabled=('OFF')

build() {
  # cd "${srcdir}"/${_realname}
  # [[ -d "${srcdir}"/build-${CARCH} ]] && rm -rf "${srcdir}"/build-${CARCH}
  # mkdir -p "${srcdir}"/build-${CARCH} && cd "${srcdir}"/build-${CARCH}

  declare -a extra_config
  declare -a extra_make_opts
  if check_option "debug" "n"; then
    extra_config+=("-DCMAKE_BUILD_TYPE=Release")
  else
    extra_config+=("-DCMAKE_BUILD_TYPE=Debug")
    extra_config+=(-DCMAKE_C_FLAGS="-g -O0 -DDEBUG -fobjc-runtime=gnustep-1.9")
    extra_config+=(-DCMAKE_C_LINK_FLAGS="-Wl,--allow-multiple-definition")
    tests_enabled=('ON')
    extra_make_opts+=("VERBOSE=1")
  fi

  MSYS2_ARG_CONV_EXCL="-DCMAKE_INSTALL_PREFIX=" \
    ${MINGW_PREFIX}/bin/cmake \
      -G'MSYS Makefiles' \
      -DCMAKE_INSTALL_PREFIX=${MINGW_PREFIX} \
      -DGNUSTEP_INSTALL_TYPE=NONE \
      "${extra_config[@]}" \
      -DCMAKE_POSITION_INDEPENDENT_CODE=OFF \
	  -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_ASM_COMPILER=clang -DCMAKE_ASM_FLAGS=-c -DTESTS=${tests_enabled} \
      ../${_realname}

  make "${extra_make_opts[@]}"
}

build
exit 0

