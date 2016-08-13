//
//  SPUInstallationInfo.m
//  Sparkle
//
//  Created by Mayur Pawashe on 4/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUInstallationInfo.h"
#import "SUAppcastItem.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

static NSString *SUAppcastItemKey = @"SUAppcastItem";
static NSString *SUCanSilentlyInstallKey = @"SUCanSilentlyInstall";

@implementation SPUInstallationInfo

@synthesize appcastItem = _appcastItem;
@synthesize canSilentlyInstall = _canSilentlyInstall;

- (instancetype)initWithAppcastItem:(SUAppcastItem *)appcastItem canSilentlyInstall:(BOOL)canSilentlyInstall
{
    self = [super init];
    if (self != nil) {
        _appcastItem = appcastItem;
        _canSilentlyInstall = canSilentlyInstall;
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)decoder
{
    SUAppcastItem *appcastItem = [decoder decodeObjectOfClass:[SUAppcastItem class] forKey:SUAppcastItemKey];
    if (appcastItem == nil) {
        return nil;
    }
    
    BOOL canSilentlyInstall = [decoder decodeBoolForKey:SUCanSilentlyInstallKey];
    return [self initWithAppcastItem:appcastItem canSilentlyInstall:canSilentlyInstall];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:self.appcastItem forKey:SUAppcastItemKey];
    [coder encodeBool:self.canSilentlyInstall forKey:SUCanSilentlyInstallKey];
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

@end
