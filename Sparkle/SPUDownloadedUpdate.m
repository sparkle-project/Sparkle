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

@synthesize updateItem = _updateItem;
@synthesize secondaryUpdateItem = _secondaryUpdateItem;

@synthesize downloadBookmarkData = _downloadBookmarkData;
@synthesize downloadToken = _downloadToken;

- (instancetype)initWithAppcastItem:(SUAppcastItem *)updateItem secondaryAppcastItem:(SUAppcastItem * _Nullable)secondaryUpdateItem downloadBookmarkData:(NSData *)downloadBookmarkData downloadToken:(NSString *)downloadToken
{
    self = [super init];
    if (self != nil) {
        _updateItem = updateItem;
        _secondaryUpdateItem = secondaryUpdateItem;
        _downloadBookmarkData = downloadBookmarkData;
        _downloadToken = [downloadToken copy];
    }
    return self;
}

@end
