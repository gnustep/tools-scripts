#!/bin/sh
echo "Setting up MSVC/GNUstep Environment"
. /c/GNUstep/x64/Debug/share/GNUstep/Makefiles/GNUstep.sh
export PATH=/c/Program\ Files/Microsoft\ Visual\ Studio/2022/Community/VC/Tools/Llvm/x64/bin:${PATH}
echo "Done"
which clang
# which cmake
