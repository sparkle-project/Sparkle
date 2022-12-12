#!/bin/sh

FRAMEWORK_PATH="${TARGET_BUILD_DIR}"/"${FULL_PRODUCT_NAME}"

# Remove any unused XPC Services

removedservices=0

if [[ "$SPARKLE_EMBED_INSTALLER_LAUNCHER_XPC_SERVICE" -eq 0 ]]; then
    rm -rf "${FRAMEWORK_PATH}"/"Versions/"${FRAMEWORK_VERSION}"/XPCServices"/"${INSTALLER_LAUNCHER_NAME}.xpc"
    removedservices=$((removedservices+1))
fi

if [[ "$SPARKLE_EMBED_DOWNLOADER_XPC_SERVICE" -eq 0 ]]; then
    rm -rf "${FRAMEWORK_PATH}"/"Versions/"${FRAMEWORK_VERSION}"/XPCServices"/"${DOWNLOADER_NAME}.xpc"
    removedservices=$((removedservices+1))
fi

if [[ "$SPARKLE_EMBED_INSTALLER_STATUS_XPC_SERVICE" -eq 0 ]]; then
    rm -rf "${FRAMEWORK_PATH}"/"Versions/"${FRAMEWORK_VERSION}"/XPCServices"/"${INSTALLER_STATUS_NAME}.xpc"
    removedservices=$((removedservices+1))
fi

if [[ "$SPARKLE_EMBED_INSTALLER_CONNECTION_XPC_SERVICE" -eq 0 ]]; then
    rm -rf "${FRAMEWORK_PATH}"/"Versions/"${FRAMEWORK_VERSION}"/XPCServices"/"${INSTALLER_CONNECTION_NAME}.xpc"
    removedservices=$((removedservices+1))
fi

if [[ "$removedservices" -eq 4 ]]; then
    rm -rf "${FRAMEWORK_PATH}"/"Versions/"${FRAMEWORK_VERSION}"/XPCServices"
    rm -rf "${FRAMEWORK_PATH}"/"XPCServices"
fi

# Remove any unused nibs

if [[ "$SPARKLE_BUILD_UI_BITS" -eq 0 ]]; then
    rm -rf "${FRAMEWORK_PATH}"/"Versions/"${FRAMEWORK_VERSION}"/Resources"/"SUStatus.nib"
    rm -rf "${FRAMEWORK_PATH}"/"Versions/"${FRAMEWORK_VERSION}"/Resources"/"Base.lproj/SUUpdateAlert.nib"
    rm -rf "${FRAMEWORK_PATH}"/"Versions/"${FRAMEWORK_VERSION}"/Resources"/"Base.lproj/SUUpdatePermissionPrompt.nib"
    rm -rf "${FRAMEWORK_PATH}"/"Versions/"${FRAMEWORK_VERSION}"/Resources"/"ReleaseNotesColorStyle.css"
fi

# Remove localization files if requested

if [[ "$SPARKLE_COPY_LOCALIZATIONS" -eq 0 ]]; then
    for dir in "${FRAMEWORK_PATH}"/"Versions/"${FRAMEWORK_VERSION}"/Resources"/*; do
        base=$(basename "$dir")
        if [[ "$base" =~ .*".lproj" ]]; then
            if [[ "$base" = "Base.lproj" ]]; then
                rm -rf "$dir/Sparkle.strings"
                # Remove Base.lproj if it's empty and the nibs have been stripped out already
                rmdir "$dir"
            else
                rm -rf "$dir"
            fi
        fi
    done
fi
