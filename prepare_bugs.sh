#!/bin/sh

cat ~/Downloads/gnustep-bugs.html | sed 's/\<h2\>//g' | sed 's/\<\/h2\>//g' |  sed 's/\<h3\>//g' | sed 's/\<\/h3\>//g' |  sed 's/\<h5\>//g' | sed 's/\<\/h5\>//g' |  sed 's/\<p\>//g' | sed 's/\<\/p\>//g' |  sed 's/\<h4\>//g' | sed 's/\<\/h4\>//g' |  sed 's/\<html\>//g' | sed 's/\<\/html\>//g' |  sed 's/\<body\>//g' | sed 's/\<\/body\>//g' > gnustep-bugs.txt