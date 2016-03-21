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
    SUInstallationFinishedStage2 = 6
};

typedef NS_ENUM(int32_t, SUUpdaterMessageType)
{
    SUSentUpdateAppcastItemData = 0,
    SUReceiveUpdateAppcastItemData = 1,
    SUResumeInstallationToStage2 = 2
};

typedef NS_ENUM(int32_t, SUInstallStatusMessageType)
{
    SUAppcastItemData = 0,
    SUWaitingOnUpdateData = 1
};

BOOL SUInstallerMessageTypeIsLegal(SUInstallerMessageType oldMessageType, SUInstallerMessageType newMessageType);

NSString *SUUpdateDriverServiceNameForHost(SUHost *host);

NSString *SUAutoUpdateServiceNameForHost(SUHost *host);

NSString *SUInstallStatusServiceNameForHost(SUHost *host, int32_t tag);

NS_ASSUME_NONNULL_END
