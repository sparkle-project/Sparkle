//
//  SPUSystemAuthorization.m
//  Sparkle
//
//  Created by Mayur Pawashe on 7/11/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUSystemAuthorization.h"
#import "SPUInstallationType.h"

BOOL SPUNeedsSystemAuthorizationAccess(NSString *path, NSString *installationType)
{
    BOOL result;
    if ([installationType isEqualToString:SPUInstallationTypeGuidedPackage]) {
        result = YES;
    } else if ([installationType isEqualToString:SPUInstallationTypeInteractivePackage]) {
        result = NO;
    } else {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        result = ![fileManager isWritableFileAtPath:path] || ![fileManager isWritableFileAtPath:[path stringByDeletingLastPathComponent]];
    }
    return result;
}
