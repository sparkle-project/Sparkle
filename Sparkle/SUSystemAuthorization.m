//
//  SUSystemAuthorization.m
//  Sparkle
//
//  Created by Mayur Pawashe on 7/11/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUSystemAuthorization.h"
#import <ServiceManagement/ServiceManagement.h>

AuthorizationRef SUCreateAuthorization(BOOL * _Nullable grantedSystemPrivilege)
{
    // This should almost always succeed, fail in unusual/rare cases
    AuthorizationRef auth = NULL;
    OSStatus createStatus = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, kAuthorizationFlagDefaults, &auth);
    if (createStatus != errAuthorizationSuccess) {
        auth = NULL;
        if (grantedSystemPrivilege != NULL) {
            *grantedSystemPrivilege = NO;
        }
    } else {
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
        if (grantedSystemPrivilege != NULL) {
            *grantedSystemPrivilege = (copyStatus == errAuthorizationSuccess);
        }
    }
    return auth;
}

BOOL SUGrantsSystemAuthorizationAccess(void)
{
    BOOL grantedSystemPrivilege = NO;
    
    AuthorizationRef auth = SUCreateAuthorization(&grantedSystemPrivilege);
    AuthorizationFree(auth, kAuthorizationFlagDefaults);
    
    return grantedSystemPrivilege;
}
