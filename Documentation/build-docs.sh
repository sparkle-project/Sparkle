#!/bin/bash

if [ "$ACTION" = "" ] ; then
    if which -s doxygen ; then
        doxygen Documentation/Doxyfile
    else
        echo "warning: Doxygen not found in PATH"
        echo "open Terminal and type this command 'brew install doxygen' then click 'enter/return' key. finally build this target again"
    fi
elif [ "$ACTION" = "clean" ] ; then
    rm -rf "$SRCROOT/Documentation/html"
fi
