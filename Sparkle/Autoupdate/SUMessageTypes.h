//
//  SUMessageTypes.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/11/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

@class SUHost;

typedef NS_ENUM(int32_t, SUInstallerMessageType)
{
    SUExtractedArchiveWithProgress = 1,
    SUArchiveExtractionFailed = 2,
    SUValidationStarted = 3,
    SUInstallationStartedStage1 = 5,
    SUInstallationFinishedStage1 = 6,
    SUInstallationFinishedStage2 = 7
};

typedef NS_ENUM(int32_t, SUUpdaterMessageType)
{
    SUResumeInstallationToStage2 = 1
};

NSString *SUUpdateDriverServiceNameForHost(SUHost *host);

NSString *SUAutoUpdateServiceNameForHost(SUHost *host);
