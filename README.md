GNUstep scripts
===

The purpose of these scripts is to simplify GNUstep installation and dependency management.  

Usage:
---
* Make sure that the tools-scripts directory is in the same directory as make, base, gui & back.
  (if you are using SVN this should be done already)
* make certain that when you execute these scripts you are in the directory above.
  These scripts act on the gnustep repos.  like so ./tools-scripts/[scriptname]
* Type, for example: ./tools-scripts/clang-build.  This will do all of the needed configuration
  using clang.
* You must be in the directory above (where all of the GNUstep related directories are) when invoking
  any script in this directory.  This is so that the scripts will have access to all of GNUstep when
  running.
* A few scripts: whitespace-cleanup, process-files, and cleanup should be executed inside the repo
  directory.

The purposes of all of the scripts is as follows:
---
* clang-build - Build GNUstep using clang
* compile-all - Build GNUstep.  With no options it will build using gcc and the built in runtime.
* windows-build - Legacy script builds GNUstep on Windows under MinGW32.
* build-* - Builds GNUstep for the given operating system represented by *
* install-dependencies-* - installs the dependencies for a given system represented by *
* setup-* - sets up the build for the system represented by *
* windows-package - packages a GNUstep application so that it can run WITHOUT having GNUstep installed
* clone-essential-repos - uses SSL to update the essential repos
* clone-essential-repos-https - uses HTTPS to update the essential repos
* update-gnustep - update gnustep from git, merge the latest if needed.
* clone-* - clone from git repositories
* whitespace-cleanup - cleanup one file
* process-files - run the specified command on the current files that have been changed.
* cleanup - whitespace cleanup and, likely, other cleanups to be done on currently changed files.

Please report any bugs you find with this set of scripts.

Thank you... GC
