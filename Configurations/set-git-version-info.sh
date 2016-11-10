#!/bin/sh
set -e

if ! which -s git ; then
    exit 0
fi

if [ -z "$SRCROOT" ] || \
   [ -z "$BUILT_PRODUCTS_DIR" ] || \
   [ -z "$INFOPLIST_PATH" ] || \
   [ -z "$CURRENT_PROJECT_VERSION" ]; then
	echo "$0: Must be run from Xcode!" 1>&2
    exit 1
fi

# Get the current Git master hash
gitversion=$(cd "$SRCROOT" ; git show-ref --abbrev heads/master | awk '{print $1}')
if [ -z "$gitversion" ] ; then
	echo "$0: Can't find a Git hash!" 1>&2
    exit 0
fi

gitversion="Sparkle $CURRENT_PROJECT_VERSION git-$gitversion"

# and use it to set the NSHumanReadableCopyright value
export PATH="$PATH:/usr/libexec"
PlistBuddy -c "Set :NSHumanReadableCopyright '$gitversion'" \
    "$BUILT_PRODUCTS_DIR/$INFOPLIST_PATH"

# CFBundleShortVersionString requires simpler version format
PlistBuddy -c "Set :CFBundleShortVersionString '$CURRENT_PROJECT_VERSION'" \
    "$BUILT_PRODUCTS_DIR/$INFOPLIST_PATH"
