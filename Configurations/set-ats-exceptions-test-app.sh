#!/bin/sh

# We should make sure ATS is off for the test app

DOWNLOADER_INFO_PLIST="${TARGET_BUILD_DIR}"/"${CONTENTS_FOLDER_PATH}"/XPCServices/"${DOWNLOADER_BUNDLE_ID}".xpc/Contents/Info.plist

#Only alter bundles if code signing is off, else we'll invalidate the signature on them
#If code signing is enabled (as in debug mode), then we rely on another script for turning ATS exceptions on for these services
#In release mode however, those services do not have ATS exceptions set up which is why we have to set up exceptions *here*
if [ -z "${CODE_SIGN_IDENTITY}" ] ; then
    /usr/libexec/PlistBuddy -c "Set :NSAppTransportSecurity:NSAllowsArbitraryLoads YES" "${DOWNLOADER_INFO_PLIST}"
fi
