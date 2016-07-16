//
//  SUInstallerLauncher.m
//  InstallerLauncher
//
//  Created by Mayur Pawashe on 4/1/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUInstallerLauncher.h"
#import "SUFileManager.h"
#import "SULog.h"
#import "SUMessageTypes.h"
#import <ServiceManagement/SMLoginItem.h>
#import "SUSystemAuthorization.h"

@implementation SUInstallerLauncher

- (void)launchInstallerAtPath:(NSString *)installerPath withHostBundleIdentifier:(NSString *)hostBundleIdentifier allowingInteraction:(BOOL)allowingInteraction completion:(void (^)(BOOL success))completionHandler
{
    dispatch_async(dispatch_get_main_queue(), ^{
        SUFileManager *fileManager = [SUFileManager defaultManager];
        
        NSURL *installerURL = [NSURL fileURLWithPath:installerPath];
        
        NSError *quarantineError = nil;
        if (![fileManager releaseItemFromQuarantineAtRootURL:installerURL error:&quarantineError]) {
            // This may or may not be a fatal error depending on if the process is sandboxed or not
            SULog(@"Failed to release quarantine on installer at %@ with error %@", installerPath, quarantineError);
        }
        
        NSString *executablePath = [[[installerPath stringByAppendingPathComponent:@"Contents"] stringByAppendingPathComponent:@"MacOS"] stringByAppendingPathComponent:@SPARKLE_RELAUNCH_TOOL_NAME];
        
        NSError *ownershipError = nil;
        if (![fileManager changeOwnerAndGroupOfItemAtRootURL:[NSURL fileURLWithPath:executablePath] toMatchURL:installerURL error:&ownershipError]) {
            // This may or may not be a fatal error
            SULog(@"Failed to change ownership on installer executable at %@ with error %@", executablePath, ownershipError);
        }
        
        NSArray *arguments = @[hostBundleIdentifier, @(allowingInteraction).stringValue];
        
        BOOL grantsSystemPrivilege = NO;
        AuthorizationRef auth = SUCreateAuthorization(&grantsSystemPrivilege);
        Boolean submittedJob = false;
        if (auth != NULL) {
            CFStringRef domain = (grantsSystemPrivilege ? kSMDomainSystemLaunchd : kSMDomainUserLaunchd);
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
            
            NSDictionary *jobDictionary = @{@"Label" : label, @"ProgramArguments" : [@[executablePath] arrayByAddingObjectsFromArray:arguments], @"EnableTransactions" : @NO, @"KeepAlive" : @{@"SuccessfulExit" : @NO}, @"RunAtLoad" : @NO, @"NICE" : @0, @"LaunchOnlyOnce": @YES, @"MachServices" : @{SUInstallerServiceNameForBundleIdentifier(hostBundleIdentifier) : @YES, SUStatusInfoServiceNameForBundleIdentifier(hostBundleIdentifier) : @YES}};
            
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
        
        completionHandler(submittedJob == true);
    });
}

@end
