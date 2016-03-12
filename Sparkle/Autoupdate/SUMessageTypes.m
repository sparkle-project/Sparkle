//
//  SUMessageTypes.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/11/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUMessageTypes.h"
#import "SUHost.h"

NSString *SUUpdateDriverServiceNameForHost(SUHost *host)
{
    return [NSString stringWithFormat:@"%@-sparkle-updater", host.bundle.bundleIdentifier];
}

NSString *SUAutoUpdateServiceNameForHost(SUHost *host)
{
    return [NSString stringWithFormat:@"%@-sparkle-installer", host.bundle.bundleIdentifier];
}
