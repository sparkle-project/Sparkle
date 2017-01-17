//
//  SPUInformationalUpdate.m
//  Sparkle
//
//  Created by Mayur Pawashe on 1/8/17.
//  Copyright © 2017 Sparkle Project. All rights reserved.
//

#import "SPUInformationalUpdate.h"


#include "AppKitPrevention.h"

@implementation SPUInformationalUpdate

// If we ever enable auto-synthesize in the future, we'll still need this synthesize
// because the property is declared in a protocol
@synthesize updateItem = _updateItem;

- (instancetype)initWithAppcastItem:(SUAppcastItem *)updateItem
{
    self = [super init];
    if (self != nil) {
        _updateItem = updateItem;
    }
    return self;
}

@end
