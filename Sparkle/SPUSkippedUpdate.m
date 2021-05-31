//
//  SPUSkippedUpdate.m
//  Sparkle
//
//  Created by Mayur Pawashe on 5/8/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#import "SPUSkippedUpdate.h"
#import "SUHost.h"
#import "SUConstants.h"
#import "SUAppcastItem.h"


#include "AppKitPrevention.h"

@implementation SPUSkippedUpdate

@synthesize minorVersion = _minorVersion;
@synthesize majorVersion = _majorVersion;

- (instancetype)initWithMinorVersion:(nullable NSString *)minorVersion majorVersion:(nullable NSString *)majorVersion
{
    self = [super init];
    if (self != nil) {
        _minorVersion = [minorVersion copy];
        _majorVersion = [majorVersion copy];
        
        assert(_minorVersion != nil || _majorVersion != nil);
    }
    return self;
}

+ (nullable SPUSkippedUpdate *)skippedUpdateForHost:(SUHost *)host
{
    NSString *minorVersion = [host objectForUserDefaultsKey:SUSkippedMinorVersionKey];
    NSString *majorVersion = [host objectForUserDefaultsKey:SUSkippedMajorVersionKey];
    
    if (minorVersion != nil || majorVersion != nil) {
        return [[SPUSkippedUpdate alloc] initWithMinorVersion:minorVersion majorVersion:majorVersion];
    } else {
        return nil;
    }
}

+ (void)clearSkippedUpdateForHost:(SUHost *)host
{
    [host setObject:nil forUserDefaultsKey:SUSkippedMinorVersionKey];
    [host setObject:nil forUserDefaultsKey:SUSkippedMajorVersionKey];
}

+ (void)skipUpdate:(SUAppcastItem *)updateItem host:(SUHost *)host
{
    if (updateItem.majorUpgrade) {
        NSString *majorVersion = updateItem.minimumAutoupdateVersion;
        assert(majorVersion != nil);
        
        [host setObject:majorVersion forUserDefaultsKey:SUSkippedMajorVersionKey];
    } else {
        NSString *version = updateItem.versionString;
        [host setObject:version forUserDefaultsKey:SUSkippedMinorVersionKey];
    }
}

@end
