//
//  SUSystemAuthorization.m
//  Sparkle
//
//  Created by Mayur Pawashe on 7/11/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUSystemAuthorization.h"
#import <ServiceManagement/ServiceManagement.h>

static BOOL SUPreflightSystemAuthorization(void)
{
    // This should almost always succeed, fail in unusual/rare cases
    AuthorizationRef auth = NULL;
    OSStatus createStatus = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, kAuthorizationFlagDefaults, &auth);
    if (createStatus != errAuthorizationSuccess) {
        return NO;
    }
    
    AuthorizationItem rightItems[] = {
        { .name = kSMRightModifySystemDaemons, .valueLength = 0, .value = NULL, .flags = 0}
    };
    
    AuthorizationRights rights = {
        .count = sizeof(rightItems) / sizeof(*rightItems),
        .items = rightItems,
    };
    
    AuthorizationFlags flags =
    (AuthorizationFlags)(kAuthorizationFlagExtendRights | kAuthorizationFlagPreAuthorize);
    
    // This will test if we can gain authorization for running utlities as root
    OSStatus copyStatus = AuthorizationCopyRights(auth, &rights, kAuthorizationEmptyEnvironment, flags, NULL);
    
    AuthorizationFree(auth, kAuthorizationFlagDefaults);
    
    return (copyStatus == errAuthorizationSuccess);
}

BOOL SUNeedsSystemAuthorizationAccess(NSString *path, BOOL guided, BOOL * _Nullable preflighted)
{
    BOOL result;
    if (SUPreflightSystemAuthorization()) {
        if (preflighted != NULL) {
            *preflighted = YES;
        }
        result = YES;
    } else if (guided) {
        result = YES;
    } else {
#pragma what about symbolic links?
        NSFileManager *fileManager = [NSFileManager defaultManager];
        result = ![fileManager isWritableFileAtPath:path] || ![fileManager isWritableFileAtPath:[path stringByDeletingLastPathComponent]];
    }
    return result;
}
