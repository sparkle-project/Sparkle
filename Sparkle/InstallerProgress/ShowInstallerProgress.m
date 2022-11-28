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
}

- (void)installerProgressShouldDisplayWithHost:(SUHost *)host
{
    // Try to retrieve localization strings from the old bundle if possible
    // Note in Sparkle 2 in the common case it should be unlikely that this progress window will show up
    // Uncommon cases where the install process may be slower are if the app to be installed is on a network mount
    // or e.g. USB mount or a different mount in general.
    // In case we fail to load the localizations we will show English strings, which is not a big deal here.
    
    NSBundle *hostSparkleBundle;
    {
        NSURL *hostSparkleURL = [host.bundle.privateFrameworksURL URLByAppendingPathComponent:@"Sparkle.framework" isDirectory:YES];
        if (hostSparkleURL == nil) {
            hostSparkleBundle = nil;
        } else {
            hostSparkleBundle = [NSBundle bundleWithURL:hostSparkleURL];
        }
    }
    
    NSString *updatingString;
    {
        NSString *updatingFormatStringFromBundle = (hostSparkleBundle != nil) ? SULocalizedStringFromTableInBundle(@"Updating %@", @"Sparkle", hostSparkleBundle, nil) : nil;

        NSString *hostNameFromBundle = host.name;
        NSString *hostName = (hostNameFromBundle != nil) ? hostNameFromBundle : @"";
        
        if (updatingFormatStringFromBundle != nil) {
            // Replacing the %@ will be a bit safer than using +[NSString stringWithFormat:]
            updatingString = [updatingFormatStringFromBundle stringByReplacingOccurrencesOfString:@"%@" withString:hostName];
        } else {
            updatingString = [@"Updating " stringByAppendingString:hostName];
        }
    }
    
    _statusController = [[SUStatusController alloc] initWithHost:host windowTitle:updatingString centerPointValue:nil minimizable:NO closable:NO];
    
    NSString *cancelUpdateTitle;
    {
        NSString *cancelUpdateTitleFromBundle = (hostSparkleBundle != nil) ?  SULocalizedStringFromTableInBundle(@"Cancel Update", @"Sparkle", hostSparkleBundle, @"") : nil;
        cancelUpdateTitle = (cancelUpdateTitleFromBundle != nil) ? cancelUpdateTitleFromBundle : @"Cancel Update";
    }
    
    [_statusController setButtonTitle:cancelUpdateTitle target:nil action:nil isDefault:NO];
    
    NSString *installingUpdateTitle;
    {
        NSString *installingUpdateTitleFromBundle = (hostSparkleBundle != nil) ?  SULocalizedStringFromTableInBundle(@"Installing update…", @"Sparkle", hostSparkleBundle, @"") : nil;
        installingUpdateTitle = (installingUpdateTitleFromBundle != nil) ? installingUpdateTitleFromBundle : @"Installing update…";
    }
    
    [_statusController beginActionWithTitle:installingUpdateTitle maxProgressValue:0 statusText:@""];
    
    [_statusController showWindow:self];
}

- (void)installerProgressShouldStop
{
    [_statusController close];
    _statusController = nil;
}

@end
