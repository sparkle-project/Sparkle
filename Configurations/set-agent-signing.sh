#!/bin/sh

AGENT_PATH="${TARGET_BUILD_DIR}"/"${CONTENTS_FOLDER_PATH}"/"MacOS/${SPARKLE_INSTALLER_PROGRESS_TOOL_NAME}.app"

#Only sign the agent app if we have code signing enabled (as we do with adhoc signatures in Debug builds for testing sandboxing)
if ! [ -z ${CODE_SIGN_IDENTITY}] ; then
    codesign --verbose -f -s "${CODE_SIGN_IDENTITY}" "${AGENT_PATH}"
fi
