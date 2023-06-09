#!/bin/sh
echo "Setting up MSVC/GNUstep Environment"
. /c/GNUstep/x64/Debug/share/GNUstep/Makefiles/GNUstep.sh
. /c/src/tools-windows-msvc/scripts/setup_path.sh
echo "Done"
which clang
which cmake

