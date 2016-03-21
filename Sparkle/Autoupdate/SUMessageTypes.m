//
//  SUMessageTypes.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/11/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUMessageTypes.h"
#import "SUHost.h"

NSString *SUAppcastItemArchiveKey = @"SUAppcastItemArchive";

BOOL SUInstallerMessageTypeIsLegal(SUInstallerMessageType oldMessageType, SUInstallerMessageType newMessageType)
{
    BOOL legal;
    switch (newMessageType) {
        case SUInstallerNotStarted:
            legal = (oldMessageType == SUInstallerNotStarted);
            break;
        case SUExtractedArchiveWithProgress:
        case SUArchiveExtractionFailed:
            legal = (oldMessageType == SUInstallerNotStarted || oldMessageType == SUExtractedArchiveWithProgress);
            break;
        case SUValidationStarted:
            legal = (oldMessageType == SUInstallerNotStarted || oldMessageType == SUExtractedArchiveWithProgress);
            break;
        case SUInstallationStartedStage1:
            legal = (oldMessageType == SUValidationStarted);
            break;
        case SUInstallationFinishedStage1:
            legal = (oldMessageType == SUInstallationStartedStage1);
            break;
        case SUInstallationFinishedStage2:
            legal = (oldMessageType == SUInstallationFinishedStage1);
            break;
    }
    return legal;
}

NSString *SUUpdateDriverServiceNameForHost(SUHost *host)
{
    return [NSString stringWithFormat:@"%@-sparkle-updater", host.bundle.bundleIdentifier];
}

NSString *SUAutoUpdateServiceNameForHost(SUHost *host)
{
    return [NSString stringWithFormat:@"%@-sparkle-installer", host.bundle.bundleIdentifier];
}
