//
//  SUMessageTypes.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/11/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

@class SUHost;

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

// Order matters; higher stages have higher values
typedef NS_ENUM(int32_t, SUUpdaterMessageType)
{
    SUResumeInstallationToStage2 = 1
};

BOOL SUInstallerMessageTypeIsLegal(SUInstallerMessageType oldMessageType, SUInstallerMessageType newMessageType);

NSString *SUUpdateDriverServiceNameForHost(SUHost *host);

NSString *SUAutoUpdateServiceNameForHost(SUHost *host);
