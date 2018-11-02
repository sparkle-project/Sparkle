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

@interface ShowInstallerProgress ()

@property (nonatomic) SUStatusController *statusController;

@end

@implementation ShowInstallerProgress

@synthesize statusController = _statusController;

- (void)installerProgressShouldDisplayWithHost:(SUHost *)host
{
    self.statusController = [[SUStatusController alloc] initWithHost:host];
    
    [self.statusController setButtonTitle:SULocalizedString(@"Cancel Update", @"") target:nil action:nil isDefault:NO];
    [self.statusController beginActionWithTitle:SULocalizedString(@"Installing update...", @"") maxProgressValue:0 statusText:@""];
    [self.statusController showWindow:self];
}

- (void)installerProgressShouldStop
{
    [self.statusController close];
    self.statusController = nil;
}

@end
