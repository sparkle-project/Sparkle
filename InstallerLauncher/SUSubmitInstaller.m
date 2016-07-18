//
//  SUSubmitInstaller.m
//  Sparkle
//
//  Created by Mayur Pawashe on 7/17/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUSubmitInstaller.h"
#import "SUFileManager.h"
#import "SULog.h"
#import "SUMessageTypes.h"
#import <ServiceManagement/ServiceManagement.h>

@implementation SUSubmitInstaller

+ (SUAuthorizationReply)submitInstallerAtPath:(NSString *)installerPath withHostBundle:(NSBundle *)hostBundle allowingInteraction:(BOOL)allowingInteraction inSystemDomain:(BOOL)systemDomain
{
    SUFileManager *fileManager = [SUFileManager defaultManager];
    
    NSURL *installerURL = [NSURL fileURLWithPath:installerPath];
    
    NSError *quarantineError = nil;
    if (![fileManager releaseItemFromQuarantineAtRootURL:installerURL error:&quarantineError]) {
        // Probably not a fatal error because we are submitting the executable through launchd
        SULog(@"Failed to release quarantine on installer at %@ with error %@", installerPath, quarantineError);
    }
    
    NSString *hostBundleIdentifier = hostBundle.bundleIdentifier;
    assert(hostBundleIdentifier != nil);
    
    NSArray<NSString *> *arguments = @[installerPath, hostBundleIdentifier, @(allowingInteraction).stringValue];
    
    AuthorizationRef auth = NULL;
    OSStatus createStatus = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, kAuthorizationFlagDefaults, &auth);
    if (createStatus != errAuthorizationSuccess) {
        auth = NULL;
        SULog(@"Failed to create authorization reference");
    }
    
    BOOL canceledAuthorization = NO;
    BOOL failedToUseSystemDomain = NO;
    if (auth != NULL && systemDomain) {
        AuthorizationItem rightItems[] = {
            { .name = kSMRightModifySystemDaemons, .valueLength = 0, .value = NULL, .flags = 0}
        };
        
        AuthorizationRights rights = {
            .count = sizeof(rightItems) / sizeof(*rightItems),
            .items = rightItems,
        };
        
        AuthorizationFlags flags =
        (AuthorizationFlags)(kAuthorizationFlagDefaults | kAuthorizationFlagExtendRights | kAuthorizationFlagPreAuthorize | kAuthorizationFlagInteractionAllowed);
        
        OSStatus copyStatus = AuthorizationCopyRights(auth, &rights, kAuthorizationEmptyEnvironment, flags, NULL);
        if (copyStatus != errAuthorizationSuccess) {
            SULog(@"Failed copying system domain rights with kSMRightModifySystemDaemons");
            failedToUseSystemDomain = YES;
            
            if (copyStatus == errAuthorizationCanceled) {
                canceledAuthorization = YES;
            }
        }
    }
    
    Boolean submittedJob = false;
    if (!failedToUseSystemDomain && auth != NULL) {
        CFStringRef domain = (systemDomain ? kSMDomainSystemLaunchd : kSMDomainUserLaunchd);
        NSString *label = [NSString stringWithFormat:@"%@-sparkle-updater", hostBundleIdentifier];
        
        // Try to remove the job from launchd if it is already running
        // We could invoke SMJobCopyDictionary() first to see if the job exists, but I'd rather avoid
        // using it because the headers indicate it may be removed one day without any replacement
        CFErrorRef removeError = NULL;
        if (!SMJobRemove(domain, (__bridge CFStringRef)(label), auth, true, &removeError)) {
            if (removeError != NULL) {
                // It's normal for a job to not be found, so this is not an interesting error
                if (CFErrorGetCode(removeError) != kSMErrorJobNotFound) {
                    SULog(@"Remove error: %@", removeError);
                }
                CFRelease(removeError);
            }
        }
        
        NSDictionary *jobDictionary = @{@"Label" : label, @"ProgramArguments" : arguments, @"EnableTransactions" : @NO, @"KeepAlive" : @{@"SuccessfulExit" : @NO}, @"RunAtLoad" : @NO, @"NICE" : @0, @"LaunchOnlyOnce": @YES, @"MachServices" : @{SUInstallerServiceNameForBundleIdentifier(hostBundleIdentifier) : @YES, SUStatusInfoServiceNameForBundleIdentifier(hostBundleIdentifier) : @YES, SUProgressAgentServiceNameForBundleIdentifier(hostBundleIdentifier) : @YES}};
        
        CFErrorRef submitError = NULL;
        submittedJob = SMJobSubmit(domain, (__bridge CFDictionaryRef)(jobDictionary), auth, &submitError);
        if (!submittedJob) {
            if (submitError != NULL) {
                SULog(@"Submit error: %@", submitError);
                CFRelease(submitError);
            }
        }
        
        AuthorizationFree(auth, kAuthorizationFlagDefaults);
    }
    
    SUAuthorizationReply reply;
    if (submittedJob == true) {
        reply = SUAuthorizationReplySuccess;
    } else if (canceledAuthorization) {
        reply = SUAuthorizationReplyCancelled;
    } else {
        reply = SUAuthorizationReplyFailure;
    }
    return reply;
}

@end
