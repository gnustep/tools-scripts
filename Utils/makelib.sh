#!/bin/bash

#
# This script generates the missing lib file using dlltool
# under msys.  This is needed to properly link some libraries
# into apps.
#

date > ./makelib.log
FILES=`ls -C1 *.dll`
for i in $FILES
do
    echo "Generating def file for ${i}..."
    gendef 2>> ./makelib.log $i
    defname=`echo $i | sed 's/dll/def/'`
    libname=`echo $i | sed 's/dll/lib/'`
    echo "Generating lib file ${libname}..."
    dlltool 2>> ./makelib.log -d ${defname} -l ${libname}
    echo "Done"
done

echo "Finished..."

exit 0
