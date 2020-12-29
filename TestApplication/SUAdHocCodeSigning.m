//
//  SUAdHocCodeSigning.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/4/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUAdHocCodeSigning.h"

@implementation SUAdHocCodeSigning

+ (BOOL)codeSignApplicationAtPath:(NSString *)applicationPath
{
    BOOL success = NO;
    @try
    {
        // ad-hoc signing with the dash
        NSArray *arguments = @[ @"--force", @"--deep", @"--sign", @"-", applicationPath ];
        NSTask *task = [NSTask launchedTaskWithLaunchPath:@"/usr/bin/codesign" arguments:arguments];
        [task waitUntilExit];
        success = (task.terminationStatus == 0);
    }
    @catch (NSException *exception)
    {
        NSLog(@"Failed to code sign application at %@", applicationPath);
        NSLog(@"Exception: %@", exception);
    }
    return success;
}

@end
