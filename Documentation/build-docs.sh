#!/bin/bash

if [ "$ACTION" = "" ] ; then
    doxygen Documentation/Doxyfile
elif [ "$ACTION" = "clean" ] ; then
    rm -rf "$SRCROOT/Documentation/html"
fi
