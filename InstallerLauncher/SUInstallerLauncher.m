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
#import "SUSystemAuthorization.h"
#import "SUSubmitInstaller.h"

@implementation SUInstallerLauncher

- (BOOL)submitProgressToolAtPath:(NSString *)progressToolPath withHostBundle:(NSBundle *)hostBundle inSystemDomainForInstaller:(BOOL)inSystemDomainForInstaller
{
    SUFileManager *fileManager = [SUFileManager defaultManager];
    
    NSURL *progressToolURL = [NSURL fileURLWithPath:progressToolPath];
    
    NSError *quarantineError = nil;
    if (![fileManager releaseItemFromQuarantineAtRootURL:progressToolURL error:&quarantineError]) {
        // This may or may not be a fatal error depending on if the process is sandboxed or not
        SULog(@"Failed to release quarantine on installer at %@ with error %@", progressToolPath, quarantineError);
    }
    
    NSString *executablePath = [[NSBundle bundleWithURL:progressToolURL] executablePath];
    assert(executablePath != nil);
    
    NSString *hostBundlePath = hostBundle.bundlePath;
    assert(hostBundlePath != nil);
    
    NSString *hostBundleIdentifier = hostBundle.bundleIdentifier;
    assert(hostBundleIdentifier != nil);
    
    NSArray<NSString *> *arguments = @[executablePath, hostBundlePath, @(inSystemDomainForInstaller).stringValue];
    
#warning support running under system domain if updater is running as root - this means we would have to try running job under a different user
    CFStringRef domain = kSMDomainUserLaunchd;
    NSString *label = [NSString stringWithFormat:@"%@-sparkle-progress", hostBundleIdentifier];
    
    AuthorizationRef auth = NULL;
    Boolean submittedJob = false;
    OSStatus createStatus = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, kAuthorizationFlagDefaults, &auth);
    if (createStatus == errAuthorizationSuccess) {
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
        
        NSMutableDictionary *jobDictionary = [[NSMutableDictionary alloc] init];
        jobDictionary[@"Label"] = label;
        jobDictionary[@"ProgramArguments"] = arguments;
        jobDictionary[@"EnableTransactions"] = @NO;
        jobDictionary[@"KeepAlive"] = @{@"SuccessfulExit" : @NO};
        jobDictionary[@"RunAtLoad"] = @NO;
        jobDictionary[@"NICE"] = @0;
        jobDictionary[@"LaunchOnlyOnce"] = @YES;
        jobDictionary[@"MachServices"] = @{SUStatusInfoServiceNameForBundleIdentifier(hostBundleIdentifier) : @YES};
        
        CFErrorRef submitError = NULL;
        submittedJob = SMJobSubmit(domain, (__bridge CFDictionaryRef)(jobDictionary), auth, &submitError);
        if (!submittedJob) {
            if (submitError != NULL) {
                SULog(@"Submit progress error: %@", submitError);
                CFRelease(submitError);
            }
        }
        
        AuthorizationFree(auth, kAuthorizationFlagDefaults);
    }
    
    return (submittedJob == true);
}

- (void)launchInstallerAtPath:(NSString *)installerPath progressToolPath:(NSString *)progressToolPath withHostBundlePath:(NSString *)hostBundlePath guidedInstallation:(BOOL)guidedInstallation allowingInteraction:(BOOL)allowingInteraction completion:(void (^)(SUAuthorizationReply))completionHandler
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSBundle *hostBundle = [NSBundle bundleWithPath:hostBundlePath];
        
        BOOL preflighted = NO;
        BOOL needsSystemAuthorization = SUNeedsSystemAuthorizationAccess(hostBundlePath, guidedInstallation, &preflighted);
        
        // if we need to use the system domain and we aren't already root and we aren't allowed interaction, then try sometime later when interaction is allowed
        if (needsSystemAuthorization && !preflighted && !allowingInteraction) {
            completionHandler(SUAuthorizationReplyAuthorizeLater);
        } else {
            BOOL submittedInstaller = ([SUSubmitInstaller submitInstallerAtPath:installerPath withHostBundle:hostBundle allowingInteraction:allowingInteraction inSystemDomain:needsSystemAuthorization] == SUAuthorizationReplySuccess);
            
            if (!submittedInstaller) {
                SULog(@"Failed to submit installer job");
            }
            
            BOOL submittedProgressTool = NO;
            if (submittedInstaller) {
                submittedProgressTool = [self submitProgressToolAtPath:progressToolPath withHostBundle:hostBundle inSystemDomainForInstaller:needsSystemAuthorization];
                
                if (!submittedProgressTool) {
                    SULog(@"Failed to submit progress tool job");
                }
            }
            
            completionHandler(submittedProgressTool ? SUAuthorizationReplySuccess : SUAuthorizationReplyFailure);
        }
    });
}

@end
