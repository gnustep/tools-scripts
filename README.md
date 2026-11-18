# GNUstep scripts

The purpose of these scripts is to simplify GNUstep installation and dependency management.  

## Usage:

* Make sure that the tools-scripts directory is in the same directory as make, base, gui & back.
  (if you are using SVN this should be done already)
* Run repository and build helper commands from the directory above
  `tools-scripts`, where the GNUstep repositories live.
* Type, for example, `./tools-scripts/gnustep clang-build` to configure and
  build using clang.
* Platform actions (`setup`, `dependencies`, `build`, and `post-install`)
  select the workspace automatically and can be invoked from any directory.
* The `whitespace-cleanup`, `process-files`, and `cleanup` commands should be
  executed inside the repository they operate on.

The platform-specific setup and build scripts are invoked through one entry point:

```
./tools-scripts/gnustep setup
./tools-scripts/gnustep dependencies
./tools-scripts/gnustep build
./tools-scripts/gnustep post-install
```

The host operating system and architecture are detected automatically. Use `--os`,
`--arch`, or `--toolchain` to override detection, and `./tools-scripts/gnustep list`
to see all available implementations. For example, an MSYS2 clang build can be
selected with:

```
./tools-scripts/gnustep build --os windows --arch x86_64 --toolchain clang
```

Platform actions run from the parent of `tools-scripts`, where the GNUstep
repositories normally live. Set `GNUSTEP_WORKSPACE_ROOT` to use another
workspace directory.

Platform implementations are organized beneath
`scripts/<action>/<os>/<architecture>/<toolchain>`. A platform-independent
architecture or toolchain is named `any` or `default`, respectively.

All other commands are organized by purpose under `scripts/commands` and are
also invoked through `gnustep`. For example:

```
./tools-scripts/gnustep clone-essential-repos
./tools-scripts/gnustep update-gnustep
./tools-scripts/gnustep windows-package MyApplication.app
```

Run `./tools-scripts/gnustep list` to see every platform implementation and
command. Some commonly used commands are:
---
* clang-build - Build GNUstep using clang
* compile-all - Build GNUstep.  With no options it will build using gcc and the built in runtime.
* windows-package - packages a GNUstep application so that it can run WITHOUT having GNUstep installed
* clone-essential-repos - clone or update the essential repos over SSH
* clone-all-repos - clone or update all listed repos over SSH
* update-gnustep - update GNUstep over SSH, then build and install it.
* clone-*-https - explicitly use HTTPS instead of SSH for cloning and updating

The default repository commands and development installer require a GitHub SSH
key. Existing checkouts are updated using the selected transport regardless of
their configured origin URL.
* whitespace-cleanup - cleanup one file
* process-files - run the specified command on the current files that have been changed.
* cleanup - whitespace cleanup and, likely, other cleanups to be done on currently changed files.



Install GNUstep dev environment
===

For the HTTPS installer, download the standalone top-level script, review it,
and run it from the directory where you want the `gnustep` workspace created.
Git and curl must already be installed.

```
curl -fsSLO https://raw.githubusercontent.com/gnustep/tools-scripts/master/gnustep-web-install
sh gnustep-web-install
```

The standalone script retrieves the installer from this repository. Inside an
existing checkout, it uses the local installer instead.

 * use ssh-agent forwarding, or have your key for GitHub locally on your dev machine and
   start ssh-agent locally.
 * have sudo configured, you may or may not want to use NOPASSWD
 * have the SSH key from GitHub accepted

Assume an empty development VM, i.e. Linux, OpenBSD, you name it:

```
mkdir ~/gnustep
cd ~/gnustep
git clone https://github.com/gnustep/tools-scripts.git
```

Review the commands before running the development installer. Once you're
confident, it's good to go:

If you're on OpenBSD, the default invocation will build with gcc against gcc libobjc.
If you want to build against libobjc2 with ARC support, before going on export WITH_ARC=yes environment variable.

```
./tools-scripts/gnustep gnustep-web-install-dev
```

Go grab a coffee, and wait a bit.

Once it finished, source GNUstep.sh and start developing:

. /usr/GNUstep/System/Library/Makefiles/GNUstep.sh


Run the dispatcher regression tests without installing or building GNUstep:

```
python3 -m unittest discover -s tests -v
```

Please report any bugs you find with this set of scripts.

Thank you... GC
