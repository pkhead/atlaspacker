#!/bin/bash
# INSTALL_DIRECTORY=/usr/local/lib/
# SYMLINK_BIN=/usr/local/bin/atlaspacker
# 
# if [ -d "$INSTALL_DIRECTORY" ]; then
#     rm -r $INSTALL_DIRECTORY
# fi
# 
# cp -r src atlaspacker
# mv atlaspacker $INSTALL_DIRECTORY
# mkdir $INSTALL_DIRECTORY

if [ -d out ]; then
    rm -r out
fi
mkdir out

cd src
zip -r ../out/atlaspacker.love *
cd ../out
zip -d atlaspacker.love cimgui/cimgui-1-89-7.dll cimgui/cimgui-1-89-7.dylib cimgui/cimgui-1-89-7.so cimgui/LICENSE.md
cp ../src/cimgui/cimgui-1-89-7.so .
