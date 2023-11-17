#!/bin/bash
INSTALL_DIR=/usr/local/lib
BIN_DIR=/usr/local/bin

if [ -d "$INSTALL_DIR/atlaspacker" ]; then
    rm -r "$INSTALL_DIR/atlaspacker"
fi

mkdir "$INSTALL_DIR/atlaspacker"
cat $(which love) out/atlaspacker.love > $INSTALL_DIR/atlaspacker/atlaspacker
chmod +x $INSTALL_DIR/atlaspacker/atlaspacker
cp out/cimgui-1-89-7.so /usr/local/lib/lua/5.1

if [ ! -f "$BIN_DIR/atlaspacker" ]; then
    ln -s $INSTALL_DIR/atlaspacker/atlaspacker $BIN_DIR/atlaspacker
fi