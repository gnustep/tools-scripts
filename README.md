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



Install GNUstep environment in one go
===

The main script `gnustep-web-install` is a bit lighter than the `gnustep-web-install-dev`
script described later. It is _still_ making a _lot_ of assumptions about your machine
being reasonably clean, and it may change your setup in an unexpected way. You're recommended
to run it on an empty machine you're happy to reinstall later: other use of this one-step
script is not recommended at this time.

The main difference is that it will not expect you to have SSH set up with private keys
known to GitHub.

Assume an empty development VM, i.e. Linux, OpenBSD, you name it:

```
mkdir ~/gnustep
cd ~/gnustep
```

with curl already installed:
```
curl -fsSL > gnustep-web-install https://raw.githubusercontent.com/gnustep/tools-scripts/refs/heads/master/gnustep-web-install
```
or on OpenBSD with ftp:
```
ftp -o gnustep-web-install https://raw.githubusercontent.com/gnustep/tools-scripts/refs/heads/master/gnustep-web-install
```

Review what the script is doing, and you may visit the other scripts it's fetching and installing. Once you're confident, it's good to go:

If you're on OpenBSD, the default invocation of ./gnustep-web-install will build with gcc against gcc libobjc.
If you want to build against libobjc2 with ARC support, before going on export WITH_ARC=yes environment variable.

```
chmod 755 gnustep-web-install
./gnustep-web-install
```

Go grab a coffee, and wait a bit.

Once it finished, source GNUstep.sh and start developing:

. /usr/GNUstep/System/Library/Makefiles/GNUstep.sh


Please report any bugs you find with this set of scripts.

Install GNUstep dev environment
===

 * use ssh-agent forwarding, or have your key for GitHub locally on your dev machine and
   start ssh-agent locally.
 * have sudo configured, you may or may not want to use NOPASSWD
 * have the SSH key from GitHub accepted

Assume an empty development VM, i.e. Linux, OpenBSD, you name it:

```
mkdir ~/gnustep
cd ~/gnustep
```

with curl already installed:
```
curl -fsSL > gnustep-web-install-dev https://raw.githubusercontent.com/gnustep/tools-scripts/refs/heads/master/gnustep-web-install-dev
```
or on OpenBSD with ftp:
```
ftp -o gnustep-web-install-dev https://raw.githubusercontent.com/gnustep/tools-scripts/refs/heads/master/gnustep-web-install-dev
```

Review what the script is doing, and you may visit the other scripts it's fetching and installing. Once you're confident, it's good to go:

If you're on OpenBSD, the default invocation of ./gnustep-web-install-dev will build with gcc against gcc libobjc.
If you want to build against libobjc2 with ARC support, before going on export WITH_ARC=yes environment variable.

```
chmod 755 gnustep-web-install-dev
./gnustep-web-install-dev
```

Go grab a coffee, and wait a bit.

Once it finished, source GNUstep.sh and start developing:

. /usr/GNUstep/System/Library/Makefiles/GNUstep.sh


Please report any bugs you find with this set of scripts.

Thank you... GC
