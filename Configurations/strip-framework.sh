#!/bin/sh

FRAMEWORK_PATH="${TARGET_BUILD_DIR}"/"${FULL_PRODUCT_NAME}"

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
