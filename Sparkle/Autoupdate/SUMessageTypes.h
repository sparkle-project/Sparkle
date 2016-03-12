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
    SUValidationFinished = 4,
    SUInstallationStartedPreparation = 5,
    SUInstallationFinishedPreparation = 6
};

typedef NS_ENUM(int32_t, SUUpdaterMessageType)
{
    SUResumeInstallationOnTermination = 1
};

NSString *SUUpdateDriverServiceNameForHost(SUHost *host);

NSString *SUAutoUpdateServiceNameForHost(SUHost *host);
