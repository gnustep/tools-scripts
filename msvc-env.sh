#!/bin/sh

setup() {
    echo "Running setup()"
    export PATH=/c/Program\ Files/LLVM/bin:${PATH}
}



echo "Setup MSVC environment..."

setup

echo "Done."

exit 0
