//
//  SUXPCServiceInfo.m
//  Sparkle
//
//  Created by Mayur Pawashe on 4/17/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUXPCServiceInfo.h"
#import "SUErrors.h"
#import "SUConstants.h"
#import "SUHost.h"

#include "AppKitPrevention.h"

BOOL SPUXPCServiceIsEnabled(NSString *enabledKey)
{
    NSBundle *mainBundle = [NSBundle mainBundle];
    SUHost *mainBundleHost = [[SUHost alloc] initWithBundle:mainBundle];
    
    return [mainBundleHost boolForInfoDictionaryKey:enabledKey];
}
