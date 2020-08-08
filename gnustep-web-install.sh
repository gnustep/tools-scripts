#!/bin/sh

# install git
echo "=== Install git..."
sudo apt-get install git

# create directory
echo "=== Create build directories..."
mkdir -p ~/Development/gnustep
cd ~/Development/gnustep
git clone git@github.com:gnustep/tools-scripts.git

# install dependencies and update gnustep
echo "=== Install dependencies..."
./tools-scripts/install-dependencies-linux

# update gnustep
echo "=== Install GNUstep..."
which clang
if [ $? -eq 1 ]; then
    echo "++ building with clang"
    ./tools-scripts/update-gnustep clang
else
    echo "++ building with gcc"
    ./tools-scripts/update-gnustep
fi

