//
//  SUUpdateSettingsWindowController.m
//  Sparkle
//
//  Created by Mayur Pawashe on 7/25/15.
//  Copyright (c) 2015 Sparkle Project. All rights reserved.
//

#import "SUUpdateSettingsWindowController.h"
#import <Sparkle/Sparkle.h>

// This class binds to various updater properties in the nib
@implementation SUUpdateSettingsWindowController

@synthesize updater = _updater;

- (NSString *)windowNibName
{
    return NSStringFromClass([self class]);
}

@end
