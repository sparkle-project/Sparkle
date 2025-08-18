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
#import "SULocalizations.h"

@implementation ShowInstallerProgress
{
    SUStatusController *_statusController;
    NSString *_updatingString;
    NSString *_cancelUpdateTitle;
    NSString *_installingUpdateTitle;
}

- (void)loadLocalizationStringsFromHost:(SUHost *)host
{
    // Try to retrieve localization strings from the old bundle if possible
    // We won't display these strings until installerProgressShouldDisplayWithHost:
    // (which will be after the update is trusted)
    // If we fail to load localizations in any way, we default to English
    
#if SPARKLE_COPY_LOCALIZATIONS
    NSBundle *hostSparkleBundle;
    {
        NSURL *hostSparkleURL = [host.bundle.privateFrameworksURL URLByAppendingPathComponent:@"Sparkle.framework" isDirectory:YES];
        if (hostSparkleURL == nil) {
            hostSparkleBundle = nil;
        } else {
            hostSparkleBundle = [NSBundle bundleWithURL:hostSparkleURL];
        }
    }
#endif
    
    NSString *updatingString;
    {
        NSString *hostNameFromBundle = host.name;
        NSString *hostName = (hostNameFromBundle != nil) ? hostNameFromBundle : @"";
        
#if SPARKLE_COPY_LOCALIZATIONS
        {
            NSString *updatingFormatStringFromBundle = (hostSparkleBundle != nil) ? SULocalizedStringFromTableInBundle(@"Updating %@", @"Sparkle", hostSparkleBundle, nil) : nil;
            
            if (updatingFormatStringFromBundle != nil) {
                // Replacing the %@ will be a bit safer than using +[NSString stringWithFormat:]
                updatingString = [updatingFormatStringFromBundle stringByReplacingOccurrencesOfString:@"%@" withString:hostName];
            } else {
                updatingString = [@"Updating " stringByAppendingString:hostName];
            }
        }
#else
        {
            updatingString = [@"Updating " stringByAppendingString:hostName];
        }
#endif
    }
    
    _updatingString = updatingString;
    
    NSString *cancelUpdateTitle;
#if SPARKLE_COPY_LOCALIZATIONS
    {
        NSString *cancelUpdateTitleFromBundle = (hostSparkleBundle != nil) ?  SULocalizedStringFromTableInBundle(@"Cancel Update", @"Sparkle", hostSparkleBundle, @"") : nil;
        cancelUpdateTitle = (cancelUpdateTitleFromBundle != nil) ? cancelUpdateTitleFromBundle : @"Cancel Update";
    }
#else
    {
        cancelUpdateTitle = @"Cancel Update";
    }
#endif
    _cancelUpdateTitle = cancelUpdateTitle;
    
    NSString *installingUpdateTitle;
#if SPARKLE_COPY_LOCALIZATIONS
    {
        NSString *installingUpdateTitleFromBundle = (hostSparkleBundle != nil) ?  SULocalizedStringFromTableInBundle(@"Installing update…", @"Sparkle", hostSparkleBundle, @"") : nil;
        installingUpdateTitle = (installingUpdateTitleFromBundle != nil) ? installingUpdateTitleFromBundle : @"Installing update…";
    }
#else
    {
        installingUpdateTitle = @"Installing update…";
    }
#endif
    
    _installingUpdateTitle = installingUpdateTitle;
}

- (void)installerProgressShouldDisplayWithHost:(SUHost *)host
{
    _statusController = [[SUStatusController alloc] initWithHost:host windowTitle:_updatingString centerPointValue:nil minimizable:NO closable:NO];
    
    [_statusController setButtonTitle:_cancelUpdateTitle target:nil action:nil isDefault:NO accessibilityIdentifier:@"SUStatusCancel"];
    
    [_statusController beginActionWithTitle:_installingUpdateTitle maxProgressValue:0 statusText:@""];
    
    [_statusController showWindow:self];
}

- (void)installerProgressShouldStop
{
    [_statusController close];
    _statusController = nil;
}

@end
