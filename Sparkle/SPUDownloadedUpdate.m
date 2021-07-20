//
//  SPUDownloadedUpdate.m
//  Sparkle
//
//  Created by Mayur Pawashe on 1/8/17.
//  Copyright © 2017 Sparkle Project. All rights reserved.
//

#import "SPUDownloadedUpdate.h"


#include "AppKitPrevention.h"

@implementation SPUDownloadedUpdate

// If we ever enable auto-synthesize in the future, we'll still need this synthesize
// because the property is declared in a protocol
@synthesize updateItem = _updateItem;
@synthesize secondaryUpdateItem = _secondaryUpdateItem;

@synthesize downloadName = _downloadName;
@synthesize temporaryDirectory = _temporaryDirectory;

- (instancetype)initWithAppcastItem:(SUAppcastItem *)updateItem secondaryAppcastItem:(SUAppcastItem * _Nullable)secondaryUpdateItem downloadName:(NSString *)downloadName temporaryDirectory:(NSString *)temporaryDirectory
{
    self = [super init];
    if (self != nil) {
        _updateItem = updateItem;
        _secondaryUpdateItem = secondaryUpdateItem;
        _downloadName = [downloadName copy];
        _temporaryDirectory = [temporaryDirectory copy];
    }
    return self;
}

@end
