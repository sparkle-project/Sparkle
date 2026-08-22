//
//  ShowInstallerProgress.m
//  Installer Progress
//
//  Created by Mayur Pawashe on 4/7/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <AppKit/AppKit.h>
#import "ShowInstallerProgress.h"
#import "SUStatusController.h"
#import "SUHost.h"

#if SPARKLE_COPY_LOCALIZATIONS
#import "SPUInstallerProgressLocalizedStrings.h"
#endif

@implementation ShowInstallerProgress
{
    SUStatusController *_statusController;
}

#if SPARKLE_COPY_LOCALIZATIONS
// SPUInstallerProgressLocalizedStringsTable is generated at development time (by Configurations/generate_progress_tool_localizations.py)
static NSDictionary<NSString *, NSString *> *SUBestMatchingInstallerProgressLocalizedStrings(void)
{
    NSArray<NSString *> *availableLocalizations = SPUInstallerProgressLocalizedStringsTable.allKeys;
    NSArray<NSString *> *preferredLocalizations = [NSBundle preferredLocalizationsFromArray:availableLocalizations];
    NSString *bestLocalization = preferredLocalizations.firstObject ?: @"en";
    return SPUInstallerProgressLocalizedStringsTable[bestLocalization] ?: SPUInstallerProgressLocalizedStringsTable[@"en"];
}
#endif

- (void)installerProgressShouldDisplayWithHost:(SUHost *)host
{
#if SPARKLE_COPY_LOCALIZATIONS
    NSDictionary<NSString *, NSString *> *localizedStrings = SUBestMatchingInstallerProgressLocalizedStrings();
#else
    NSDictionary<NSString *, NSString *> *localizedStrings = @{};
#endif

    NSString *hostNameFromBundle = host.name;
    NSString *hostName = (hostNameFromBundle != nil) ? hostNameFromBundle : @"";

    NSString *updatingFormatString = localizedStrings[@"Updating %@"] ?: @"Updating %@";
    NSString *updatingString = [updatingFormatString stringByReplacingOccurrencesOfString:@"%@" withString:hostName];

    NSString *cancelUpdateTitle = localizedStrings[@"Cancel Update"] ?: @"Cancel Update";

    NSString *installingUpdateTitle = localizedStrings[@"Installing update…"] ?: @"Installing update…";
    
    _statusController = [[SUStatusController alloc] initWithHost:host windowTitle:updatingString centerPointValue:nil minimizable:NO closable:NO];
    
    [_statusController setButtonTitle:cancelUpdateTitle target:nil action:nil isDefault:NO accessibilityIdentifier:@"SUStatusCancel"];
    
    [_statusController beginActionWithTitle:installingUpdateTitle maxProgressValue:0 statusText:@""];
    
    [_statusController showWindow:self];
}

- (void)installerProgressShouldStop
{
    [_statusController close];
    _statusController = nil;
}

@end
