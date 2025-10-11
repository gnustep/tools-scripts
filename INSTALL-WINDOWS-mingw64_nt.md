# Installing GNUstep on Windows 10 (MSYS2 MinGW-w64 / mingw64_nt)

This guide explains how to build and install GNUstep on Windows 10 using the MSYS2 MinGW-w64 (mingw64_nt) environment.

## Overview

- Install MSYS2 (MinGW-w64 64-bit)
- Update MSYS2 packages
- Clone this repository (or use your local copy)
- Run the repository helper scripts: `install-dependencies-mingw64_nt`, `setup-mingw64_nt`, `build-mingw64_nt`, and `post-install-mingw64_nt`
- Verify the installation with small smoke tests

## Prerequisites

- Windows 10 (64-bit)
- Administrative privileges for installing some packages (when required)
- Internet access for `pacman` and `git`
- Recommended free disk space: 10–30 GB (builds can be large)

Note: Use the "MSYS2 MinGW 64-bit" shell supplied by MSYS2 (this is the mingw64 environment). Do not use the plain MSYS shell, PowerShell, or CMD for the build steps.

## 1. Install MSYS2 (MinGW-w64)

1. Download the MSYS2 installer from <https://www.msys2.org/>.
2. Run the installer and follow the instructions (default installation path is recommended).
3. Open the "MSYS2 MinGW 64-bit" shortcut from the Start menu. This opens the mingw64 environment we need.

## 2. Update MSYS2 packages (important)

In the MSYS2 MinGW 64-bit shell run:

```bash
# Update the package database and core system packages (may ask to restart the shell)
pacman -Syu

# After closing and re-opening the MSYS2 MinGW 64-bit shell (if pacman requested it), finish updates:
pacman -Su
```

If `pacman` asks you to restart the shell while running `-Syu`, close and re-open the MSYS2 MinGW 64-bit shell and run `pacman -Su` again.

## 3. (Optional) Configure Git line endings

To avoid CRLF problems with shell scripts in the repo, configure Git inside MSYS2:

```bash
# inside MSYS2 MinGW 64-bit shell
git config --global core.autocrlf false
```

Or clone with the option:

```bash
git -c core.autocrlf=false clone https://github.com/gnustep/tools-scripts.git
```

## 4. Install Git (if needed) and clone this repository

MSYS2 typically provides `git`. If it is not installed, install it and clone:

```bash
# inside MSYS2 MinGW 64-bit shell
pacman -S --needed git
git clone https://github.com/gnustep/tools-scripts.git
# Do not change directory; we'll invoke the helper scripts by path (./tools-scripts/)
```

If you already have a local copy of the repository, `cd` into that folder instead.

## 5. Install required MinGW packages (use the repo script)

This repository includes helper scripts specifically for the mingw64 target:

- `install-dependencies-mingw64_nt` — installs required MSYS2/Mingw packages via `pacman`
- `setup-mingw64_nt` — configures GNUstep Makefiles and environment
- `build-mingw64_nt` — builds the GNUstep stack
- `post-install-mingw64_nt` — optional post-install tasks

Run them from the MSYS2 MinGW 64-bit shell in the repository root:

```bash
chmod +x ./tools-scripts/install-dependencies-mingw64_nt ./tools-scripts/setup-mingw64_nt ./tools-scripts/build-mingw64_nt ./tools-scripts/post-install-mingw64_nt
./tools-scripts/install-dependencies-mingw64_nt
```

Notes:

- The script will call `pacman` to install required packages (GCC, make, pkg-config, cmake, etc.). Let it run and install.
- If you prefer, open `install-dependencies-mingw64_nt` to see the package list and install them manually with `pacman -S`.

## 6. Run the setup script to configure the environment

Run the setup script from the repository root:

```bash
./tools-scripts/setup-mingw64_nt
```

This script typically:

- Creates or copies GNUstep Makefiles into `/mingw64/etc/GNUstep/Makefiles` (or the appropriate MinGW prefix)
- Produces helper shell fragments you can `source` to get GNUstep environment variables

If the script prints the path to a helper file (for example `gnustep_env.sh`), source it to set up the environment in your current shell. Example:

```bash
# example; follow the actual file the script prints
source /mingw64/etc/GNUstep/Runtime/gnustep.sh || true
# or if the script wrote a helper inside the repo
source ./gnustep-env.sh
```

If the script does not produce a sourceable file, it will at least set up Makefiles and other configuration files required by the build.

## 7. Build the tree

Use the build driver to build the GNUstep components:

```bash
# From repository root inside MSYS2 MinGW 64-bit shell
./tools-scripts/build-mingw64_nt
```

Notes:

- Building everything can take a long time (hours on slower machines).
- Scripts commonly honor `MAKEFLAGS` or accept `-j` options. For example, to build with 4 jobs:

```bash
MAKEFLAGS='-j4' ./build-mingw64_nt
```

- If the build fails, capture the first error in the logs — typical causes are missing packages, wrong shell (not using mingw64), or antivirus interference.

## 8. Post-install

If the repository provides a `post-install-mingw64_nt` script, run it to perform final packaging or copy the built artifacts into their final locations:

```bash
./tools-scripts/post-install-mingw64_nt
```

Review the script to see whether it installs into `/mingw64`, a staging area, or creates packages.

## Quick verification / smoke tests

1. Confirm toolchain and paths:

```bash
which gcc
gcc --version

which make
make --version

ls /mingw64/bin | grep -Ei 'gcc|g\+\+|gnustep'
```

2. Build and run a tiny native example to ensure `gcc` works:

```bash
cat > hello.c <<'EOF'
#include <stdio.h>
int main(void){ puts("Hello from mingw64"); return 0; }
EOF
gcc -o hello.exe hello.c
./hello.exe
```

3. If you built GNUstep libraries, try compiling a tiny Objective-C example or running any small GNUstep tool the build produced. The exact test depends on which components you built.

## Common troubleshooting

- Wrong shell: ensure you're using the "MSYS2 MinGW 64-bit" shell.
- `pacman` slow or failing: try again and consider changing mirrors in `/etc/pacman.d/mirrorlist`.
- Git CRLF issues: set `core.autocrlf=false` or re-clone with that option.
- Antivirus: temporarily whitelist MSYS2 and the build folders during builds.
- Path length problems: enable long paths in Windows 10 (Group Policy or registry) if you see path-length errors.
- Disk space: builds can be large; free more space or build only the components you need.
- Permission errors for `pacman -S`: run the MSYS2 shell as Administrator if required.
- For build failures, inspect logs around the first error. Missing headers indicate missing `mingw-w64-x86_64-*-dev` packages (install the corresponding `mingw-w64-x86_64-...` pacman package).

## Performance tips

- Use parallel builds with `MAKEFLAGS='-jN'` or pass `-jN` to supported `make` invocations.
- Build only the components you need (edit `build-mingw64_nt` or run component-specific targets) to save time.
- Use an SSD and multiple cores for significantly faster builds.

## Repository files you will use

- `install-dependencies-mingw64_nt` — installs MSYS2/mingw packages via `pacman`.
- `setup-mingw64_nt` — configures GNUstep Makefiles and environment for mingw64.
- `build-mingw64_nt` — builds the GNUstep stack for mingw64.
- `post-install-mingw64_nt` — post-installation and packaging tasks.

Run those scripts from the repository root inside the MSYS2 MinGW 64-bit shell.

## Example full session (copyable)

Open the MSYS2 MinGW 64-bit shell and run the following commands:

```bash
# update system
pacman -Syu
# reopen shell if pacman requested it, then finish updates
pacman -Su

# install git if needed, clone repo
pacman -S --needed git
git -c core.autocrlf=false clone https://github.com/gnustep/tools-scripts.git

# invoke helper scripts from the repository path (do not cd into it)
chmod +x ./tools-scripts/install-dependencies-mingw64_nt ./tools-scripts/setup-mingw64_nt ./tools-scripts/build-mingw64_nt ./tools-scripts/post-install-mingw64_nt
./tools-scripts/install-dependencies-mingw64_nt
./tools-scripts/setup-mingw64_nt
# optional: parallel build (adjust -j to match your CPU)
MAKEFLAGS='-j4' ./tools-scripts/build-mingw64_nt
./tools-scripts/post-install-mingw64_nt
```

## Next steps / how I can help

If you want, I can:

- Inspect the `install-dependencies-mingw64_nt`, `setup-mingw64_nt`, and `build-mingw64_nt` scripts in this repository and produce a tailored command list.
- Add a short Windows-specific README or integrate this file into the repo's main `README.md` with a link.
- Help debug build failures — paste the first error and I'll analyze it and propose fixes.

---

*File added on: October 11, 2025*
