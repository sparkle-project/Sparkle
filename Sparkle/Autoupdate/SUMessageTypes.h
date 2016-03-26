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
    SURequestInstallationParameters = 1,
    SUExtractedArchiveWithProgress = 2,
    SUArchiveExtractionFailed = 3,
    SUValidationStarted = 4,
    SUInstallationStartedStage1 = 5,
    SUInstallationFinishedStage1 = 6,
    SUInstallationFinishedStage2 = 7
};

typedef NS_ENUM(int32_t, SUUpdaterMessageType)
{
    SUInstallationData = 0,
    SUSentUpdateAppcastItemData = 1,
    SUReceiveUpdateAppcastItemData = 2,
    SUResumeInstallationToStage2 = 3
};

typedef NS_ENUM(int32_t, SUInstallStatusMessageType)
{
    SUAppcastItemData = 0,
    SUWaitingOnUpdateData = 1
};

BOOL SUInstallerMessageTypeIsLegal(SUInstallerMessageType oldMessageType, SUInstallerMessageType newMessageType);

NSString *SUUpdateDriverServiceNameForBundleIdentifier(NSString *bundleIdentifier);

NSString *SUAutoUpdateServiceNameForBundleIdentifier(NSString *bundleIdentifier);

NS_ASSUME_NONNULL_END
