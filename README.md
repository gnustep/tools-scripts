GNUstep scripts
===

The purpose of these scripts is to simplify GNUstep installation and dependency management.  

Usage:
* Make sure that the scripts directory is in the same directory as make, base, gui & back.  (if you are using SVN this should be done already)
* Type, for example: ./tools-scripts/clang-build.  This will do all of the needed configuration using clang.
* You must be in the directory above (where all of the GNUstep related directories are) when invoking any script in this directory.  This is so that the scripts will have access to all of GNUstep when running.

The purposes of all of the scripts is as follows:
* clang-build - Build GNUstep using clang
* compile-all - Build GNUstep.  With no options it will build using gcc and the built in runtime.
* install-dependencies - should pull down all of the dependencies GNUstep needs.   There are versions of this for different operating systems.
* windows-build - Builds GNUstep on Windows under MinGW32.
* msys-build - Builds GNUstep for Windows under MSYS2 (MinGW64).
* macos-build - Builds GNUstep for macOS/Darwin targets

Please report any bugs you find with this set of scripts.

Thank you...
