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
    SUExtractionStarted = 1,
    SUExtractedArchiveWithProgress = 2,
    SUArchiveExtractionFailed = 3,
    SUValidationStarted = 4,
    SUInstallationStartedStage1 = 5,
    SUInstallationFinishedStage1 = 6,
    SUInstallationFinishedStage2 = 7,
    SUInstallationFinishedStage3 = 8,
    SUUpdaterAlivePing = 9
};

typedef NS_ENUM(int32_t, SUUpdaterMessageType)
{
    SUInstallationData = 0,
    SUSentUpdateAppcastItemData = 1,
    SUResumeInstallationToStage2 = 2,
    SUUpdaterAlivePong = 3
};

BOOL SUInstallerMessageTypeIsLegal(SUInstallerMessageType oldMessageType, SUInstallerMessageType newMessageType);

NSString *SUInstallerServiceNameForBundleIdentifier(NSString *bundleIdentifier);

NSString *SUStatusInfoServiceNameForBundleIdentifier(NSString *bundleIdentifier);

NSString *SUProgressAgentServiceNameForBundleIdentifier(NSString *bundleIdentifier);

NS_ASSUME_NONNULL_END
