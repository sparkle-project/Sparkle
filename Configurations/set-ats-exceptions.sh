#!/bin/sh

# http://stackoverflow.com/questions/32390228/is-it-possible-to-disable-ats-in-ios-9-just-for-debug-environment
INFOPLIST="${TARGET_BUILD_DIR}"/"${INFOPLIST_PATH}"
case "${SPARKLE_ALLOW_ARBITRARY_HTTP_LOADS}" in
"YES"|"1")
/usr/libexec/PlistBuddy -c "Set :NSAppTransportSecurity:NSAllowsArbitraryLoads YES" "${INFOPLIST}"
;;
"NO"|"0")
/usr/libexec/PlistBuddy -c "Set :NSAppTransportSecurity:NSAllowsArbitraryLoads NO" "${INFOPLIST}"
;;
esac
