Refactor: OS-specific scripts
=================================

What's changed
---------------

- Per-OS wrapper scripts were added under `os-scripts/<target>/`.
- A dispatcher `run-for-os.sh` determines the OS (or accepts one explicitly) and runs the
  appropriate script.
- A helper `make-scripts-executable.sh` sets executable permissions on the wrappers.

How to use
----------

1. Make wrappers executable:

```bash
./make-scripts-executable.sh
```

2. Use the dispatcher, for example:

```bash
./run-for-os.sh install         # auto-detects platform
./run-for-os.sh build mingw64_nt
```

Notes
-----

This refactor adds thin wrappers and a dispatcher to keep compatibility while making it
easier to manage OS-specific code. If you prefer the old behaviour, scripts still exist
at the repository root and can be used directly.
