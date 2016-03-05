//
//  SUUpdateSettingsWindowController.m
//  Sparkle
//
//  Created by Mayur Pawashe on 7/25/15.
//  Copyright (c) 2015 Sparkle Project. All rights reserved.
//

#import "SUUpdateSettingsWindowController.h"
#import <Sparkle/Sparkle.h>

@interface SUUpdateSettingsWindowController ()

@property (nonatomic) IBOutlet SUStandardUpdaterController *updaterController;

@end

@implementation SUUpdateSettingsWindowController

@synthesize updaterController = _updaterController;

- (NSString *)windowNibName
{
    return NSStringFromClass([self class]);
}

- (IBAction)checkForUpdates:(id __unused)sender
{
    [self.updaterController checkForUpdates:nil];
}

@end
