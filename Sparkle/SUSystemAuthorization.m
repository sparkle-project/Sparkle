//
//  SUSystemAuthorization.m
//  Sparkle
//
//  Created by Mayur Pawashe on 7/11/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUSystemAuthorization.h"
#import "SUInstallationType.h"

BOOL SUNeedsSystemAuthorizationAccess(NSString *path, NSString *installationType)
{
    BOOL result;
    if ([installationType isEqualToString:SUInstallationTypeGuidedPackage]) {
        result = YES;
    } else if ([installationType isEqualToString:SUInstallationTypeInteractivePackage]) {
        result = NO;
    } else {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        result = ![fileManager isWritableFileAtPath:path] || ![fileManager isWritableFileAtPath:[path stringByDeletingLastPathComponent]];
    }
    return result;
}
