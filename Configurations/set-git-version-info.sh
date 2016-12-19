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

version="$CURRENT_PROJECT_VERSION"

# Get version in format 1.x.x-commits-hash
gitversion=$( cd "$SRCROOT"; git describe --tags --match '[12].*' || true )
if [ -z "$gitversion" ] ; then
    echo "$0: Can't find a Git hash!" 1>&2
    exit 0
fi

# remove everything before the first "-" to keep the hash part only
versionsuffix=${gitversion#*-};
if [ "$versionsuffix" != "$gitversion" ]; then
    version="$version $versionsuffix"
fi

# and use it to set the CFBundleShortVersionString value
export PATH="$PATH:/usr/libexec"
PlistBuddy -c "Set :CFBundleShortVersionString '$version'" \
    "$BUILT_PRODUCTS_DIR/$INFOPLIST_PATH"
