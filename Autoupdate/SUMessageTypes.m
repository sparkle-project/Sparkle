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

// Tags added to the bundle identifier which is used as Mach service names
// These should be very short because length restrictions exist on earlier versions of macOS
#define SPARKLE_INSTALLER_TAG @"-spki"
#define SPARKLE_STATUS_TAG @"-spks"
#define SPARKLE_PROGRESS_TAG @"-spkp"
#define SPARKLE_PROGRESS_LAUNCH_INSTALLER_TAG @"-spkl"

// macOS 10.8 at least can't handle service names that are 64 characters or longer
// This was fixed some point after 10.8, but I'm not sure if it was fixed in 10.9 or 10.10 or 10.11
// If we knew when it was fixed, this could only be relevant to OS versions prior to that
#define MAX_SERVICE_NAME_LENGTH 63u

BOOL SUInstallerMessageTypeIsLegal(SUInstallerMessageType oldMessageType, SUInstallerMessageType newMessageType)
{
    BOOL legal;
    switch (newMessageType) {
        case SUInstallerNotStarted:
            legal = (oldMessageType == SUInstallerNotStarted);
            break;
        case SUExtractionStarted:
            legal = (oldMessageType == SUInstallerNotStarted);
            break;
        case SUExtractedArchiveWithProgress:
        case SUArchiveExtractionFailed:
            legal = (oldMessageType == SUExtractionStarted || oldMessageType == SUExtractedArchiveWithProgress);
            break;
        case SUValidationStarted:
            legal = (oldMessageType == SUExtractionStarted || oldMessageType == SUExtractedArchiveWithProgress);
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
        case SUInstallationFinishedStage3:
            legal = (oldMessageType == SUInstallationFinishedStage2);
            break;
        case SUUpdaterAlivePing:
            // Having this state being dependent on other installation states would make the complicate our logic
            // So just always allow this type of message
            legal = YES;
            break;
    }
    return legal;
}

static NSString *SUServiceNameWithTag(NSString *tagName, NSString *bundleIdentifier)
{
    NSString *serviceName = [bundleIdentifier stringByAppendingString:tagName];
    NSUInteger length = MIN(serviceName.length, MAX_SERVICE_NAME_LENGTH);
    // If the service name is too long, cut off the beginning rather than cutting off the end
    // This should lead to a more unique name
    return [serviceName substringFromIndex:serviceName.length - length];
}

NSString *SUInstallerServiceNameForBundleIdentifier(NSString *bundleIdentifier)
{
    return SUServiceNameWithTag(SPARKLE_INSTALLER_TAG, bundleIdentifier);
}

NSString *SUStatusInfoServiceNameForBundleIdentifier(NSString *bundleIdentifier)
{
    return SUServiceNameWithTag(SPARKLE_STATUS_TAG, bundleIdentifier);
}

NSString *SUProgressAgentServiceNameForBundleIdentifier(NSString *bundleIdentifier)
{
    return SUServiceNameWithTag(SPARKLE_PROGRESS_TAG, bundleIdentifier);
}

NSString *SUProgressAgentLauncherServiceNameForBundleIdentifier(NSString *bundleIdentifier)
{
    return SUServiceNameWithTag(SPARKLE_PROGRESS_LAUNCH_INSTALLER_TAG, bundleIdentifier);
}
