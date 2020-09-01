#!/bin/sh

APP_NAME=DataBasin
APP_BUNDLE=$APP_NAME.app
DEST_DIR=/c/Users/$LOGNAME/Desktop
APP_DIR=$DEST_DIR/$APP_BUNDLE
GS_CONF_MASTER=windows-GNUstep.conf

echo Creating Self-contained package for Windows for $APP_NAME

echo Copying $APP_BUNDLE in $DEST_DIR
cp -R $APP_BUNDLE "$DEST_DIR"


echo Copying DLLs from /bin and /mingw/bin
cp $(find /bin -name *.dll) "$APP_DIR"
cp $(find /mingw/bin -name *.dll) "$APP_DIR"
cp $(find /local -name *.dll) "$APP_DIR"

echo Copying the GNUstep Directory into $APP_BUNDLE
mkdir -p "$APP_DIR"/GNUstep
cp -R /GNUstep/* "$APP_DIR"/GNUstep/

echo cleaning up CVS files
find "$APP_DIR" -name .svn -print0 | xargs -0 rm -r
find "$APP_DIR" -name .cvs -print0 | xargs -0 rm -r
find "$APP_DIR" -name .git -print0 | xargs -0 rm -r

echo cleaning up other files
find "$APP_DIR" -name stamp.make -print0 | xargs -0 rm

echo Copying GNUstep.conf file
cp $GS_CONF_MASTER "$APP_DIR"/GNUstep.conf
rm -rf  "$APP_DIR"/GNUstep/etc

echo Copying Windows manifest
cp $APP_NAME.exe.manifest $APP_DIR

echo Moving Library DLLs from the GNUstep tree to $APP_BUNDLE
mv "$APP_DIR"/GNUstep/Local/Tools/*.dll "$APP_DIR"/
mv "$APP_DIR"/GNUstep/System/Tools/*.dll "$APP_DIR"/

echo Removing Network folder...
rm -rf "$APP_DIR"/GNUstep/Network

echo Removing Headers
rm -rf "$APP_DIR"/GNUstep/Local/Library/Headers
rm -rf "$APP_DIR"/GNUstep/System/Library/Headers
find "$APP_DIR"/GNUstep -name Headers -print0 | xargs -0 rm -r

echo Removing installed applications...
rm -rf "$APP_DIR"/GNUstep/Local/Applications
rm -rf "$APP_DIR"/GNUstep/System/Applications

echo Removing Fonts
rm -rf "$APP_DIR"/GNUstep/Local/Library/Fonts
rm -rf "$APP_DIR"/GNUstep/System/Library/Fonts

echo Removing Documentation
rm -rf "$APP_DIR"/GNUstep/System/man
rm -rf "$APP_DIR"/GNUstep/Local/Library/Documentation
rm -rf "$APP_DIR"/GNUstep/System/Library/Documentation

echo Removing Makefiles
rm -rf "$APP_DIR"/GNUstep/System/Library/Makefiles

# Check that your app doesn't use one of these!
echo Removing unused frameworks and its libraries
rm -rf "$APP_DIR"/GNUstep/Local/Library/Frameworks/RSSKit.framework
rm -rf "$APP_DIR"/GNUstep/Local/Library/Libraries/libRSSKit*
rm -rf "$APP_DIR"/GNUstep/Local/Library/Frameworks/SimpleWebKit.framework
rm -rf "$APP_DIR"/GNUstep/Local/Library/Libraries/libSimpleWebKit*
rm -rf "$APP_DIR"/SimpleWebKit*
rm -rf "$APP_DIR"/GNUstep/System/Library/Frameworks/SimpleWebKit.framework
rm -rf "$APP_DIR"/GNUstep/Local/Library/Cynthiune
rm -rf "$APP_DIR"/GNUstep/Local/Library/ApplicationSupport/GSTest
rm -rf "$APP_DIR"/GNUstep/Local/Library/Bundles/libgmodel.bundle


echo Removing known Application and Developer tool traces
echo Removing Addresses
rm -rf "$APP_DIR"/GNUstep/Local/Library/Frameworks/AddressView.framework
rm -rf "$APP_DIR"/GNUstep/System/Library/Frameworks/AddressView.framework
rm -rf "$APP_DIR"/GNUstep/Local/Library/Frameworks/Addresses.framework
rm -rf "$APP_DIR"/GNUstep/System/Library/Frameworks/Addresses.framework
echo Removing Preferences resources
rm -rf "$APP_DIR"/GNUstep/Local/Library/Frameworks/PreferencePanes.framework
rm -rf "$APP_DIR"/GNUstep/System/Library/Frameworks/PreferencePanes.framework
rm -rf "$APP_DIR"/GNUstep/Local/Library/Bundles/*.prefPane
rm -rf "$APP_DIR"/GNUstep/System/Library/Bundles/*.prefPane
rm "$APP_DIR"/GNUstep/System/Tools/SystemPreferences
rm -f "$APP_DIR"/GNUstep/System/Library/Libraries/libPreferencePanes.*
echo Removing ProjectCenter resources
rm -rf "$APP_DIR"/GNUstep/Local/Library/Frameworks/ProjectCenter.framework
rm -rf "$APP_DIR"/GNUstep/System/Library/Frameworks/ProjectCenter.framework
rm -f "$APP_DIR"/GNUstep/Local/Library/Libraries/libProjectCenter*
rm -f "$APP_DIR"/GNUstep/System/Library/Libraries/libProjectCenter*
rm "$APP_DIR"/GNUstep/System/Tools/ProjectCenter
echo Removing Gorm resources
rm -f "$APP_DIR"/GNUstep/Local/Library/Libraries/libGorm*
rm -f "$APP_DIR"/GNUstep/System/Library/Libraries/libGorm*
rm "$APP_DIR"/GNUstep/System/Tools/Gorm
echo Removing GWorkspace resources
rm -f "$APP_DIR"/GNUstep/Local/Tools/fswatcher.exe
rm -f "$APP_DIR"/GNUstep/System/Tools/fswatcher.exe
rm -f "$APP_DIR"/GNUstep/Local/Tools/ddbd.exe
rm -f "$APP_DIR"/GNUstep/System/Tools/ddbd.exe
rm -rf "$APP_DIR"/GNUstep/Local/Library/Services/thumbnailer.service
rm -rf "$APP_DIR"/GNUstep/System/Library/Services/thumbnailer.service
rm -f "$APP_DIR"/GNUstep/Local/Library/Libraries/libFSNode*
rm -f "$APP_DIR"/GNUstep/System/Library/Libraries/libFSNode*
rm -f "$APP_DIR"/GNUstep/Local/Library/Libraries/libInspector*
rm -rf "$APP_DIR"/GNUstep/System/Library/Libraries/libInspector*
rm -rf "$APP_DIR"/GNUstep/Local/Library/Libraries/libOperation*
rm -rf "$APP_DIR"/GNUstep/System/Library/Libraries/libOperation*
rm -rf "$APP_DIR"/GNUstep/Local/Library/Bundles/ImageThumbnailer.thumb
rm -rf "$APP_DIR"/GNUstep/System/Library/Bundles/ImageThumbnailer.thumb
rm -rf "$APP_DIR"/GNUstep/Local/Library/Bundles/ImageViewer.inspector
rm -rf "$APP_DIR"/GNUstep/System/Library/Bundles/ImageViewer.inspector
rm -rf "$APP_DIR"/GNUstep/Local/Library/Bundles/FModule*
rm -rf "$APP_DIR"/GNUstep/System/Library/Bundles/FModule*
rm -rf "$APP_DIR"/GNUstep/Local/Library/Bundles/NSTIFFViewer.inspector
rm -rf "$APP_DIR"/GNUstep/System/Library/Bundles/NSTIFFViewer.inspector
rm -rf "$APP_DIR"/GNUstep/Local/Library/Bundles/NSRTFViewer.inspector
rm -rf "$APP_DIR"/GNUstep/System/Library/Bundles/NSRTFViewer.inspector
rm -rf "$APP_DIR"/GNUstep/Local/Library/Frameworks/Operation.framework
rm -rf "$APP_DIR"/GNUstep/System/Library/Frameworks/Operation.framework
rm -rf "$APP_DIR"/GNUstep/Local/Library/Frameworks/FSNode.framework
rm -rf "$APP_DIR"/GNUstep/System/Library/Frameworks/FSNode.framework
rm -rf "$APP_DIR"/GNUstep/Local/Library/Frameworks/Inspector.framework
rm -rf "$APP_DIR"/GNUstep/System/Library/Frameworks/Inspector.framework
rm -rf "$APP_DIR"/GNUstep/System/Library/Bundles/AppViewer.inspector
rm -rf "$APP_DIR"/GNUstep/System/Library/Bundles/FolderViewer.inspector
rm -rf "$APP_DIR"/GNUstep/System/Library/Bundles/IBViewViewer.inspector
rm -rf "$APP_DIR"/GNUstep/System/Library/Bundles/SoundViewer.inspector
rm -rf "$APP_DIR"/GNUstep/System/Library/Bundles/RtfViewer.inspector
rm -rf "$APP_DIR"/GNUstep/System/Library/Bundles/NSColorViewer.inspector
rm -rf "$APP_DIR"/GNUstep/System/Library/Bundles/Role.extinfo
rm -rf "$APP_DIR"/GNUstep/System/Library/Bundles/MDModuleAnnotations.mdm
rm "$APP_DIR"/GNUstep/Local/Tools/Recycler
rm "$APP_DIR"/GNUstep/System/Tools/Recycler
rm "$APP_DIR"/GNUstep/System/Tools/wopen.exe
rm "$APP_DIR"/GNUstep/System/Tools/searchtool.exe
rm "$APP_DIR"/GNUstep/System/Tools/GWorkspace
rm -f "$APP_DIR"/GNUstep/System/Library/Libraries/libDBKit.*

echo Removing developer libraries and tools 
rm "$APP_DIR"/libsvn*.dll
rm -rf "$APP_DIR"/GNUstep/System/share
rm "$APP_DIR"/GNUstep/System/Tools/debugapp
rm "$APP_DIR"/GNUstep/System/Tools/autogsdoc.exe
rm "$APP_DIR"/GNUstep/System/Tools/make_strings.exe
rm "$APP_DIR"/GNUstep/System/Tools/plparse.exe
rm "$APP_DIR"/GNUstep/System/Tools/sfparse.exe

echo Removing specific libraries
rm "$APP_DIR"/Gorm*.dll
rm "$APP_DIR"/Addresses*.dll
rm "$APP_DIR"/AddressView*.dll
rm "$APP_DIR"/Operation*.dll
rm "$APP_DIR"/ProjectCenter*.dll
rm "$APP_DIR"/PreferencePanes*.dll
rm "$APP_DIR"/RSSKit*.dll
rm "$APP_DIR"/Cynthiune*.dll
rm "$APP_DIR"/FSNode*.dll
rm "$APP_DIR"/Inspector*.dll
rm "$APP_DIR"/DBKit*.dll

rm "$APP_DIR"/GNUstep/Local/Tools/AClock
rm "$APP_DIR"/GNUstep/Local/Tools/AddressManager
rm "$APP_DIR"/GNUstep/Local/Tools/GFractal
