//
//  SUApplicationInfo.m
//  Sparkle
//
//  Created by Mayur Pawashe on 2/28/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUApplicationInfo.h"

@implementation SPUApplicationInfo

+ (BOOL)isBackgroundApplication:(NSApplication *)application
{
    return (application.activationPolicy == NSApplicationActivationPolicyAccessory);
}

@end
