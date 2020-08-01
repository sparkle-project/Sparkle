#!/bin/bash

if [ "$ACTION" = "" ] ; then
    if which -s doxygen ; then
        doxygen Documentation/Doxyfile
    else
        echo "warning: Doxygen not found in PATH"
        echo "open Terminal and type 'brew install doxygen', then press enter. once installation is complete, try building this target again."
    fi
elif [ "$ACTION" = "clean" ] ; then
    rm -rf "$SRCROOT/Documentation/html"
fi
