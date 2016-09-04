//
//  SPUDownloadedUpdate.m
//  Sparkle
//
//  Created by Mayur Pawashe on 7/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUDownloadedUpdate.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

@implementation SPUDownloadedUpdate

@synthesize updateItem = _updateItem;
@synthesize downloadName = _downloadName;
@synthesize temporaryDirectory = _temporaryDirectory;

- (instancetype)initWithAppcastItem:(SUAppcastItem *)updateItem downloadName:(NSString *)downloadName temporaryDirectory:(NSString *)temporaryDirectory
{
    self = [super init];
    if (self != nil) {
        _updateItem = updateItem;
        _downloadName = [downloadName copy];
        _temporaryDirectory = [temporaryDirectory copy];
    }
    return self;
}

@end
