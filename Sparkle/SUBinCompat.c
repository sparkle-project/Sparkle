//
//  SUBinCompat.c
//  Sparkle
//
//  Created by C.W. Betts on 8/2/14.
//  Copyright (c) 2014 Sparkle Project. All rights reserved.
//  Used to keep binary compatibility with older versions of Sparkle
//

// No other headers are included, especially not the SUConstants header:
// The declarations here would conflict with the constants.
#include <MacTypes.h>


extern OSStatus SUAppcastParseError;
extern OSStatus SUNoUpdateError;
extern OSStatus SUAppcastError;
extern OSStatus SURunningFromDiskImageError;
extern OSStatus SUTemporaryDirectoryError;
extern OSStatus SUUnarchivingError;
extern OSStatus SUSignatureError;
extern OSStatus SUFileCopyFailure;
extern OSStatus SUAuthenticationFailure;
extern OSStatus SUMissingUpdateError;
extern OSStatus SUMissingInstallerToolError;
extern OSStatus SURelaunchError;
extern OSStatus SUInstallationError;
extern OSStatus SUDowngradeError;

OSStatus SUAppcastParseError = 1000;
OSStatus SUNoUpdateError = 1001;
OSStatus SUAppcastError = 1002;
OSStatus SURunningFromDiskImageError = 1003;
OSStatus SUTemporaryDirectoryError = 2000;
OSStatus SUUnarchivingError = 3000;
OSStatus SUSignatureError = 3001;
OSStatus SUFileCopyFailure = 4000;
OSStatus SUAuthenticationFailure = 4001;
OSStatus SUMissingUpdateError = 4002;
OSStatus SUMissingInstallerToolError = 4003;
OSStatus SURelaunchError = 4004;
OSStatus SUInstallationError = 4005;
OSStatus SUDowngradeError = 4006;
