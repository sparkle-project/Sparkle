#!/bin/sh
set -e

if ! which -s git ; then
    exit 0
fi

if [ -z "$PROJECT_DIR" ] || \
   [ -z "$BUILT_PRODUCTS_DIR" ] || \
   [ -z "$INFOPLIST_PATH" ] || \
   [ -z "$MARKETING_VERSION" ]; then
	echo "$0: Must be run from Xcode!" 1>&2
    exit 1
fi

version="$MARKETING_VERSION"

# Get version in format 1.x.x-commits-hash
gitversion=$( cd "$PROJECT_DIR"; git describe --tags --match '[12].*' || true )
if [ -z "$gitversion" ] ; then
    echo "$0: Can't find a Git hash!" 1>&2
    exit 0
fi

# remove everything before the second last "-" to keep the hash part only
versionsuffix=$( echo "${gitversion}" | sed -E 's/.+((-[^.]+){2})$/\1/' )
if [ "$versionsuffix" != "$gitversion" ]; then
    version="$version$versionsuffix"
fi

# and use it to set the CFBundleShortVersionString value
export PATH="$PATH:/usr/libexec"

if [ -f "$BUILT_PRODUCTS_DIR/$INFOPLIST_PATH" ] ; then
    oldversion=$(PlistBuddy -c "Print :CFBundleShortVersionString" "$BUILT_PRODUCTS_DIR/$INFOPLIST_PATH")
fi
if [ "$version" != "$oldversion" ] ; then
    PlistBuddy -c "Set :CFBundleShortVersionString '$version'" \
        "$BUILT_PRODUCTS_DIR/$INFOPLIST_PATH"
fi
