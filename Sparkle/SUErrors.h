//
//  SUErrors.h
//  Sparkle
//
//  Created by C.W. Betts on 10/13/14.
//  Copyright (c) 2014 Sparkle Project. All rights reserved.
//

#ifndef SUERRORS_H
#define SUERRORS_H

#if __has_feature(modules)
@import Foundation;
#else
#import <Foundation/Foundation.h>
#endif
#import "SUExport.h"

/**
 * Error domain used by Sparkle
 */
SU_EXPORT extern NSString *const SUSparkleErrorDomain;
/**
 * User info key for update validation error
 *
 * If an update could not be found because none of the items in
 * the feed were valid, the value in the user info dictionary
 * for this key will be set to an error that describes in more
 * detail why the item was not valid (e.g because the item
 * is not compatible with the host os).
 */
SU_EXPORT extern NSString *const SUSparkleUpdateValidationErrorKey;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wc++98-compat"
typedef NS_ENUM(OSStatus, SUError) {
    // Appcast phase errors.
    SUAppcastParseError = 1000,
    SUNoUpdateError = 1001,
    SUAppcastError = 1002,
    SURunningFromDiskImageError = 1003,

    // Download phase errors.
    SUTemporaryDirectoryError = 2000,
    SUDownloadError = 2001,

    // Extraction phase errors.
    SUUnarchivingError = 3000,
    SUSignatureError = 3001,
    
    // Installation phase errors.
    SUFileCopyFailure = 4000,
    SUAuthenticationFailure = 4001,
    SUMissingUpdateError = 4002,
    SUMissingInstallerToolError = 4003,
    SURelaunchError = 4004,
    SUInstallationError = 4005,
    SUDowngradeError = 4006,
    SUInstallationCancelledError = 4007,
    
    // System phase errors
    SUSystemPowerOffError = 5000
};
#pragma clang diagnostic pop

/**
 * Error domain used by Sparkle Updates Validation
 */
SU_EXPORT extern NSString *const SUSparkleUpdateValidationErrorDomain;

/**
 * User Info Key for SUUpdateValidationErrorIncompatibleHostOSTooOld error
 * Its value is set to the minimum required OS string
 */
SU_EXPORT extern NSString *const SUSparkleUpdateValidationErrorInfoMinOSVersionKey;
/**
 * User Info Key for SUUpdateValidationErrorIncompatibleHostOSTooNew error
 * Its value is set to the maximum supported OS string
 */
SU_EXPORT extern NSString *const SUSparkleUpdateValidationErrorInfoMaxOSVersionKey;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wc++98-compat"
typedef NS_ENUM(OSStatus, SUUpdateValidationError) {
    //Incompatible Host
    SUUpdateValidationErrorIncompatibleHostOSType = 1000,
    SUUpdateValidationErrorIncompatibleHostOSTooOld = 1001,
    SUUpdateValidationErrorIncompatibleHostOSTooNew = 1002,
};
#pragma clang diagnostic pop

#endif
