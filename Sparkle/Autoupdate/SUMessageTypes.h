//
//  SUMessageTypes.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/11/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SUHost;

extern NSString *SUAppcastItemArchiveKey;

// Order matters; higher stages have higher values.
typedef NS_ENUM(int32_t, SUInstallerMessageType)
{
    SUInstallerNotStarted = 0,
    SUExtractedArchiveWithProgress = 1,
    SUArchiveExtractionFailed = 2,
    SUValidationStarted = 3,
    SUInstallationStartedStage1 = 4,
    SUInstallationFinishedStage1 = 5,
    SUInstallationFinishedStage2 = 6,
    SUInstallationFinishedStage3 = 7
};

typedef NS_ENUM(int32_t, SUUpdaterMessageType)
{
    SUInstallationData = 0,
    SUSentUpdateAppcastItemData = 1,
    SUResumeInstallationToStage2 = 2
};

BOOL SUInstallerMessageTypeIsLegal(SUInstallerMessageType oldMessageType, SUInstallerMessageType newMessageType);

NSString *SUAutoUpdateServiceNameForBundleIdentifier(NSString *bundleIdentifier);

NSString *SUStatusInfoServiceNameForBundleIdentifier(NSString *bundleIdentifier);

NS_ASSUME_NONNULL_END
