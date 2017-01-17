//
//  SPUSystemAuthorization.m
//  Sparkle
//
//  Created by Mayur Pawashe on 7/11/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUSystemAuthorization.h"
#import "SPUInstallationType.h"
#import "SUFileManager.h"


#include "AppKitPrevention.h"

BOOL SPUNeedsSystemAuthorizationAccess(NSString *path, NSString *installationType)
{
    BOOL needsAuthorization;
    if ([installationType isEqualToString:SPUInstallationTypeGuidedPackage]) {
        needsAuthorization = YES;
    } else if ([installationType isEqualToString:SPUInstallationTypeInteractivePackage]) {
        needsAuthorization = NO;
    } else {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        BOOL hasWritability = [fileManager isWritableFileAtPath:path] && [fileManager isWritableFileAtPath:[path stringByDeletingLastPathComponent]];
        if (!hasWritability) {
            needsAuthorization = YES;
        } else {
            // Just because we have writability access does not mean we can set the correct owner/group
            // Test if we can set the owner/group on a temporarily created file
            // If we can, then we can probably perform an update without authorization
            
            NSString *tempFilename = @"permission_test" ;
            
            SUFileManager *suFileManager = [[SUFileManager alloc] init];
            NSURL *tempDirectoryURL = [suFileManager makeTemporaryDirectoryWithPreferredName:tempFilename appropriateForDirectoryURL:[NSURL fileURLWithPath:NSTemporaryDirectory()] error:NULL];
            
            if (tempDirectoryURL == nil) {
                // I don't imagine this ever happening but in case it does, requesting authorization may be the better option
                needsAuthorization = YES;
            } else {
                NSURL *tempFileURL = [tempDirectoryURL URLByAppendingPathComponent:tempFilename];
                if (![[NSData data] writeToURL:tempFileURL atomically:NO]) {
                    // Obvious indicator we may need authorization
                    needsAuthorization = YES;
                } else {
                    needsAuthorization = ![suFileManager changeOwnerAndGroupOfItemAtRootURL:tempFileURL toMatchURL:[NSURL fileURLWithPath:path] error:NULL];
                }
                
                [suFileManager removeItemAtURL:tempDirectoryURL error:NULL];
            }
        }
    }
    return needsAuthorization;
}
