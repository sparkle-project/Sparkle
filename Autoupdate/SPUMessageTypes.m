//
//  SPUMessageTypes.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/11/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUMessageTypes.h"
#import "SUHost.h"


#include "AppKitPrevention.h"

NSString *SPUAppcastItemArchiveKey = @"SPUAppcastItemArchive";

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

BOOL SPUInstallerMessageTypeIsLegal(SPUInstallerMessageType oldMessageType, SPUInstallerMessageType newMessageType)
{
    BOOL legal;
    switch (newMessageType) {
        case SPUInstallerNotStarted:
            legal = (oldMessageType == SPUInstallerNotStarted);
            break;
        case SPUExtractionStarted:
            legal = (oldMessageType == SPUInstallerNotStarted);
            break;
        case SPUExtractedArchiveWithProgress:
        case SPUArchiveExtractionFailed:
            legal = (oldMessageType == SPUExtractionStarted || oldMessageType == SPUExtractedArchiveWithProgress);
            break;
        case SPUValidationStarted:
            legal = (oldMessageType == SPUExtractionStarted || oldMessageType == SPUExtractedArchiveWithProgress);
            break;
        case SPUInstallationStartedStage1:
            legal = (oldMessageType == SPUValidationStarted);
            break;
        case SPUInstallationFinishedStage1:
            legal = (oldMessageType == SPUInstallationStartedStage1);
            break;
        case SPUInstallationFinishedStage2:
            legal = (oldMessageType == SPUInstallationFinishedStage1);
            break;
        case SPUInstallationFinishedStage3:
            legal = (oldMessageType == SPUInstallationFinishedStage2);
            break;
        case SPUUpdaterAlivePing:
            // Having this state being dependent on other installation states would make the complicate our logic
            // So just always allow this type of message
            legal = YES;
            break;
    }
    return legal;
}

static NSString *SPUServiceNameWithTag(NSString *tagName, NSString *bundleIdentifier)
{
    NSString *serviceName = [bundleIdentifier stringByAppendingString:tagName];
    NSUInteger length = MIN(serviceName.length, MAX_SERVICE_NAME_LENGTH);
    // If the service name is too long, cut off the beginning rather than cutting off the end
    // This should lead to a more unique name
    return [serviceName substringFromIndex:serviceName.length - length];
}

NSString *SPUInstallerServiceNameForBundleIdentifier(NSString *bundleIdentifier)
{
    return SPUServiceNameWithTag(SPARKLE_INSTALLER_TAG, bundleIdentifier);
}

NSString *SPUStatusInfoServiceNameForBundleIdentifier(NSString *bundleIdentifier)
{
    return SPUServiceNameWithTag(SPARKLE_STATUS_TAG, bundleIdentifier);
}

NSString *SPUProgressAgentServiceNameForBundleIdentifier(NSString *bundleIdentifier)
{
    return SPUServiceNameWithTag(SPARKLE_PROGRESS_TAG, bundleIdentifier);
}
