#/bin/bash

MY_PATH="`dirname $0`"
cd "$MY_PATH/../"

xcodebuild -project Sparkle.xcodeproj -target finish_installation -configuration Release build

cd "$MY_PATH/../build/Release/"

/usr/bin/tar -czf "$MY_PATH/finish_installation.app.tar.gz" "finish_installation.app"