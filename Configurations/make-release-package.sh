#!/bin/bash
set -e

# Tests the code signing validity of the extracted products within the provided path.
# This guards against our archives being corrupt / created incorrectly.
function verify_code_signatures() {
    verification_directory="$1"
    check_aux_apps="$2"

    if  [[ -z "$verification_directory" ]]; then
        echo "Provided verification directory does not exist" >&2
        exit 1
    fi

    # Search the current directory for all instances of the framework to verify them (XCFrameworks can have multiple copies of a framework for different platforms).
    find "${verification_directory}" -name "Sparkle.framework" -type d -exec codesign --verify -vvv --deep {} \;
    
    if [ "$check_aux_apps" = true ] ; then
        codesign --verify -vvv --deep "${verification_directory}/sparkle.app"
        codesign --verify -vvv --deep "${verification_directory}/Sparkle Test App.app"
    fi
    codesign --verify -vvv --deep "${verification_directory}/bin/BinaryDelta"
    codesign --verify -vvv --deep "${verification_directory}/bin/generate_appcast"
    codesign --verify -vvv --deep "${verification_directory}/bin/sign_update"
    codesign --verify -vvv --deep "${verification_directory}/bin/generate_keys"
}

if [ "$ACTION" = "" ] ; then
    rm -rf "$CONFIGURATION_BUILD_DIR/staging"
    rm -rf "$CONFIGURATION_BUILD_DIR/staging-spm"
    rm -f "Sparkle-$MARKETING_VERSION.tar.xz"
    rm -f "Sparkle-$MARKETING_VERSION.tar.bz2"
    rm -f "Sparkle-for-Swift-Package-Manager.zip"

    mkdir -p "$CONFIGURATION_BUILD_DIR/staging"
    mkdir -p "$CONFIGURATION_BUILD_DIR/staging-spm"
    cp "$PROJECT_DIR/CHANGELOG" "$PROJECT_DIR/LICENSE" "$PROJECT_DIR/INSTALL" "$PROJECT_DIR/Resources/SampleAppcast.xml" "$CONFIGURATION_BUILD_DIR/staging"
    cp "$PROJECT_DIR/CHANGELOG" "$PROJECT_DIR/LICENSE" "$PROJECT_DIR/INSTALL" "$PROJECT_DIR/Resources/SampleAppcast.xml" "$CONFIGURATION_BUILD_DIR/staging-spm"
    cp -R "$PROJECT_DIR/bin" "$CONFIGURATION_BUILD_DIR/staging"
    cp "$CONFIGURATION_BUILD_DIR/BinaryDelta" "$CONFIGURATION_BUILD_DIR/staging/bin"
    cp "$CONFIGURATION_BUILD_DIR/generate_appcast" "$CONFIGURATION_BUILD_DIR/staging/bin"
    cp "$CONFIGURATION_BUILD_DIR/generate_keys" "$CONFIGURATION_BUILD_DIR/staging/bin"
    cp "$CONFIGURATION_BUILD_DIR/sign_update" "$CONFIGURATION_BUILD_DIR/staging/bin"
    cp -R "$CONFIGURATION_BUILD_DIR/Sparkle Test App.app" "$CONFIGURATION_BUILD_DIR/staging"
    cp -R "$CONFIGURATION_BUILD_DIR/sparkle.app" "$CONFIGURATION_BUILD_DIR/staging"
    cp -R "$CONFIGURATION_BUILD_DIR/Sparkle.framework" "$CONFIGURATION_BUILD_DIR/staging"
    cp -R "$CONFIGURATION_BUILD_DIR/Sparkle.xcframework" "$CONFIGURATION_BUILD_DIR/staging-spm"

    mkdir -p "$CONFIGURATION_BUILD_DIR/staging/Symbols"

    # Only copy dSYMs for Release builds, but don't check for the presence of the actual files
    # because missing dSYMs in a release build SHOULD trigger a build failure
    if [ "$CONFIGURATION" = "Release" ] ; then
        cp -R "$CONFIGURATION_BUILD_DIR/BinaryDelta.dSYM" "$CONFIGURATION_BUILD_DIR/staging/Symbols"
        
        cp -R "$CONFIGURATION_BUILD_DIR/generate_appcast.dSYM" "$CONFIGURATION_BUILD_DIR/staging/Symbols"
        
        cp -R "$CONFIGURATION_BUILD_DIR/generate_keys.dSYM" "$CONFIGURATION_BUILD_DIR/staging/Symbols"
                
        cp -R "$CONFIGURATION_BUILD_DIR/sign_update.dSYM" "$CONFIGURATION_BUILD_DIR/staging/Symbols"
        
        cp -R "$CONFIGURATION_BUILD_DIR/Sparkle Test App.app.dSYM" "$CONFIGURATION_BUILD_DIR/staging/Symbols"
        
        cp -R "$CONFIGURATION_BUILD_DIR/sparkle.app.dSYM" "$CONFIGURATION_BUILD_DIR/staging/Symbols"
        
        cp -R "$CONFIGURATION_BUILD_DIR/Sparkle.framework.dSYM" "$CONFIGURATION_BUILD_DIR/staging/Symbols"
        
        cp -R "$CONFIGURATION_BUILD_DIR/Autoupdate.dSYM" "$CONFIGURATION_BUILD_DIR/staging/Symbols"
                
        cp -R "$CONFIGURATION_BUILD_DIR/Updater.app.dSYM" "$CONFIGURATION_BUILD_DIR/staging/Symbols"
                
        cp -R "$CONFIGURATION_BUILD_DIR/${INSTALLER_LAUNCHER_NAME}.xpc.dSYM" "$CONFIGURATION_BUILD_DIR/staging/Symbols"
                
        cp -R "$CONFIGURATION_BUILD_DIR/${DOWNLOADER_NAME}.xpc.dSYM" "$CONFIGURATION_BUILD_DIR/staging/Symbols"
    fi
    cp -R "$CONFIGURATION_BUILD_DIR/staging/bin" "$CONFIGURATION_BUILD_DIR/staging-spm"

    cd "$CONFIGURATION_BUILD_DIR/staging"

    rm -rf "/tmp/sparkle-extract"
    mkdir -p "/tmp/sparkle-extract"

    # Sorted file list groups similar files together, which improves tar compression
    find . \! -type d | rev | sort | rev | tar --no-xattrs -cJvf "../Sparkle-$MARKETING_VERSION.tar.xz" --files-from=-
        
    # Copy archived distribution for CI
    cp -f "../Sparkle-$MARKETING_VERSION.tar.xz" "../sparkle_dist.tar.xz"

    # Extract archive for testing binary validity
    tar -xf "../Sparkle-$MARKETING_VERSION.tar.xz" -C "/tmp/sparkle-extract"

    # Test code signing validity of the extracted products
    # This guards against our archives being corrupt / created incorrectly
    verify_code_signatures "/tmp/sparkle-extract" true

    rm -rf "/tmp/sparkle-extract"
    rm -rf "$CONFIGURATION_BUILD_DIR/staging"

    # Get latest git tag
    cd "$PROJECT_DIR"
    latest_git_tag=$( git describe --tags --abbrev=0 || true )

    if [ -n "$latest_git_tag" ] ; then
        # Generate zip containing the xcframework for SPM
        rm -rf "/tmp/sparkle-spm-extract"
        mkdir -p "/tmp/sparkle-spm-extract"
        cd "$CONFIGURATION_BUILD_DIR/staging-spm"
        # rm -rf "$CONFIGURATION_BUILD_DIR/Sparkle.xcarchive"
        ditto -c -k --zlibCompressionLevel 9 --rsrc . "../Sparkle-for-Swift-Package-Manager.zip"

        # Test code signing validity of the extracted Swift package
        # This guards against our archives being corrupt / created incorrectly
        ditto -x -k "../Sparkle-for-Swift-Package-Manager.zip" "/tmp/sparkle-spm-extract"
        verify_code_signatures "/tmp/sparkle-spm-extract" false

        rm -rf "/tmp/sparkle-spm-extract"
        rm -rf "$CONFIGURATION_BUILD_DIR/staging-spm"
        
        cd "$PROJECT_DIR"
    
        # Check semantic versioning
        if [[ $latest_git_tag =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-((0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*)(\.(0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*))*))?(\\+([0-9a-zA-Z-]+(\.[0-9a-zA-Z-]+)*))?$ ]]; then
            echo "Tag $latest_git_tag follows semantic versioning"
        else
            echo "ERROR: Tag $latest_git_tag does not follow semantic versioning! SPM will not be able to resolve the repository" >&2
            exit 1
        fi
        
            # Generate new Package manifest, podspec, and carthage files
        cd "$CONFIGURATION_BUILD_DIR"
        cp "$PROJECT_DIR/Package.swift" "$CONFIGURATION_BUILD_DIR"
        cp "$PROJECT_DIR/Sparkle.podspec" "$CONFIGURATION_BUILD_DIR"
        cp "$PROJECT_DIR/Carthage-dev.json" "$CONFIGURATION_BUILD_DIR"
    fi
    
    if [ -z "$latest_git_tag" ] ; then
        echo "warning: No git repository found so skipping updating package management files"
    elif [ "$XCODE_VERSION_MAJOR" -ge "1200" ]; then
        # is equivalent to shasum -a 256 FILE
        spm_checksum=$(swift package compute-checksum "Sparkle-for-Swift-Package-Manager.zip")
        rm -rf ".build"
        sed -E -i '' -e "/let tag/ s/\".+\"/\"$latest_git_tag\"/" -e "/let version/ s/\".+\"/\"$MARKETING_VERSION\"/" -e "/let checksum/ s/[[:xdigit:]]{64}/$spm_checksum/" "Package.swift"
        cp "Package.swift" "$PROJECT_DIR"
        echo "Package.swift updated with the following values:"
        echo "Version: $MARKETING_VERSION"
        echo "Tag: $latest_git_tag"
        echo "Checksum: $spm_checksum"

        sed -E -i '' -e "/s\.version.+=/ s/\".+\"/\"$MARKETING_VERSION\"/" "Sparkle.podspec"
        
        "$PROJECT_DIR/Configurations/update-carthage.py" "Carthage-dev.json" "$MARKETING_VERSION"
        cp "Sparkle.podspec" "$PROJECT_DIR"
        # Note the Carthage-dev.json file will finally be copied to the website repo in Carthage/Sparkle.json in the end
        cp "Carthage-dev.json" "$PROJECT_DIR"
        echo "Sparkle.podspec and Carthage-dev.json updated with following values:"
        echo "Version: $MARKETING_VERSION"
    else
        echo "warning: Xcode version $XCODE_VERSION_ACTUAL does not support computing checksums for Swift Packages. Please update the Package manifest manually."
    fi

    rm -rf "$CONFIGURATION_BUILD_DIR/staging-spm"
fi
