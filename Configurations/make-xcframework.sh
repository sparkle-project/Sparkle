#!/bin/bash

# Deleting old products
rm -rd "$BUILT_PRODUCTS_DIR/Sparkle.xcarchive"
rm -rd "$BUILT_PRODUCTS_DIR/Sparkle.xcframework"

xcodebuild archive -scheme Sparkle -archivePath "$BUILT_PRODUCTS_DIR/Sparkle.xcarchive" BUILD_LIBRARY_FOR_DISTRIBUTION=YES SKIP_INSTALL=NO

if [ $XCODE_VERSION_MAJOR -ge "1200" ]; then
xcodebuild -create-xcframework -framework "$BUILT_PRODUCTS_DIR/Sparkle.xcarchive/Products/Library/Frameworks/Sparkle.framework" -debug-symbols "$BUILT_PRODUCTS_DIR/Sparkle.xcarchive/dSYMs/Sparkle.framework.dSYM" -debug-symbols "$BUILT_PRODUCTS_DIR/Sparkle.xcarchive/dSYMs/Autoupdate.dSYM" -debug-symbols "$BUILT_PRODUCTS_DIR/Sparkle.xcarchive/dSYMs/Updater.app.dSYM" -debug-symbols "$BUILT_PRODUCTS_DIR/Sparkle.xcarchive/dSYMs/$INSTALLER_LAUNCHER_NAME.xpc.dSYM" -debug-symbols "$BUILT_PRODUCTS_DIR/Sparkle.xcarchive/dSYMs/$DOWNLOADER_NAME.xpc.dSYM" -output "$BUILT_PRODUCTS_DIR/Sparkle.xcframework"
else
echo "warning: Your Xcode version does not support bundling dSYMs in XCFrameworks directly. You should copy them manually into the XCFramework."
echo "note: cp '$BUILT_PRODUCTS_DIR/Sparkle.xcarchive/dSYMs/Sparkle.framework.dSYM' '$BUILT_PRODUCTS_DIR/Sparkle.xcframework/your_architecture/dSYMs'"
xcodebuild -create-xcframework -framework "$BUILT_PRODUCTS_DIR/Sparkle.xcarchive/Products/Library/Frameworks/Sparkle.framework" -output "$BUILT_PRODUCTS_DIR/Sparkle.xcframework"
fi
