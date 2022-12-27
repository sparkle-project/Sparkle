//
//  SPUInstallationInfo.m
//  Sparkle
//
//  Created by Mayur Pawashe on 4/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUInstallationInfo.h"
#import "SUAppcastItem.h"


#include "AppKitPrevention.h"

static NSString *SUAppcastItemKey = @"SUAppcastItem";
static NSString *SUCanSilentlyInstallKey = @"SUCanSilentlyInstall";
static NSString *SUSystemDomainKey = @"SUSystemDomain";

@implementation SPUInstallationInfo

@synthesize appcastItem = _appcastItem;
@synthesize canSilentlyInstall = _canSilentlyInstall;
@synthesize systemDomain = _systemDomain;

- (instancetype)initWithAppcastItem:(SUAppcastItem *)appcastItem canSilentlyInstall:(BOOL)canSilentlyInstall systemDomain:(BOOL)systemDomain
{
    self = [super init];
    if (self != nil) {
        _appcastItem = appcastItem;
        _canSilentlyInstall = canSilentlyInstall;
        _systemDomain = systemDomain;
    }
    return self;
}

- (instancetype)initWithAppcastItem:(SUAppcastItem *)appcastItem canSilentlyInstall:(BOOL)canSilentlyInstall
{
    return [self initWithAppcastItem:appcastItem canSilentlyInstall:canSilentlyInstall systemDomain:NO];
}

- (nullable instancetype)initWithCoder:(NSCoder *)decoder
{
    SUAppcastItem *appcastItem = [decoder decodeObjectOfClass:[SUAppcastItem class] forKey:SUAppcastItemKey];
    if (appcastItem == nil) {
        return nil;
    }
    
    BOOL canSilentlyInstall = [decoder decodeBoolForKey:SUCanSilentlyInstallKey];
    BOOL systemDomain = [decoder decodeBoolForKey:SUSystemDomainKey];
    return [self initWithAppcastItem:appcastItem canSilentlyInstall:canSilentlyInstall systemDomain:systemDomain];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_appcastItem forKey:SUAppcastItemKey];
    [coder encodeBool:_canSilentlyInstall forKey:SUCanSilentlyInstallKey];
    [coder encodeBool:_systemDomain forKey:SUSystemDomainKey];
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

@end
