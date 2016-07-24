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
#import "SUBundleIcon.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

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

- (SUAuthorizationReply)submitInstallerAtPath:(NSString *)installerPath withHostBundle:(NSBundle *)hostBundle authorizationPrompt:(NSString *)authorizationPrompt allowingInteraction:(BOOL)allowingInteraction inSystemDomain:(BOOL)systemDomain
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
        SULog(@"Failed to create authorization reference: %d", createStatus);
    }
    
    BOOL canceledAuthorization = NO;
    BOOL failedToUseSystemDomain = NO;
    if (auth != NULL && systemDomain) {
        // See Apple's 'EvenBetterAuthorizationSample' sample code and
        // https://developer.apple.com/library/mac/technotes/tn2095/_index.html#//apple_ref/doc/uid/DTS10003110-CH1-SECTION7
        // We can set a custom right name for authenticating as an administrator
        // Using this right rather than using something like kSMRightModifySystemDaemons allows us to present a better worded prompt
        
        const char *rightName = [[NSString stringWithFormat:@"%@.sparkle-auth", hostBundleIdentifier] UTF8String];
        assert(rightName != NULL);
        
        OSStatus getRightResult = AuthorizationRightGet(rightName, NULL);
        if (getRightResult == errAuthorizationDenied) {
            if (AuthorizationRightSet(auth, rightName, (__bridge CFTypeRef _Nonnull)(@(kAuthorizationRuleAuthenticateAsAdmin)), (__bridge CFStringRef _Nullable)(authorizationPrompt), NULL, NULL) != errAuthorizationSuccess) {
                SULog(@"Failed to make auth right set");
            }
        }
        
        AuthorizationItem right = { .name = rightName, .valueLength = 0, .value = NULL, .flags = 0 };
        AuthorizationRights rights = { .count = 1, .items = &right };
        
        AuthorizationFlags flags = (AuthorizationFlags)(kAuthorizationFlagExtendRights | kAuthorizationFlagInteractionAllowed);
        
        AuthorizationItem iconAuthorizationItem = {.name = kAuthorizationEnvironmentIcon, .valueLength = 0, .value = NULL, .flags = 0};
        AuthorizationEnvironment authorizationEnvironment = {.count = 0, .items = NULL};
        
        // Find a 32x32 image representation of the icon, and write out a PNG version of it to a temporary location
        // Then use the icon (if one is available) for the authorization prompt
        // NSImage is not used because it relies on AppKit
        NSURL *tempIconDestinationURL = nil;
        NSURL *iconURL = [SUBundleIcon iconURLForBundle:hostBundle];
        if (iconURL != nil) {
            CGImageSourceRef imageSource = CGImageSourceCreateWithURL((CFURLRef)iconURL, (CFDictionaryRef)@{});
            if (imageSource != NULL) {
                size_t imageCount = CGImageSourceGetCount(imageSource);
                for (size_t imageIndex = 0; imageIndex < imageCount; imageIndex++) {
                    CFDictionaryRef cfProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, imageIndex, (CFDictionaryRef)@{});
                    NSDictionary *properties = (__bridge NSDictionary *)(cfProperties);
                    
                    NSNumber *pixelWidth = properties[(const NSString *)kCGImagePropertyPixelWidth];
                    NSNumber *pixelHeight = properties[(const NSString *)kCGImagePropertyPixelHeight];
                    
                    // If we don't find a 32x32 image representation, then we don't provide an icon
                    // Don't try to make up with it by eg: converting an image representation to this size
                    // The app developer should be providing the icon representation.
                    // The authorization API may not take other size dimensions.
                    NSNumber *targetDimension = @32;
                    if ([pixelWidth isKindOfClass:[NSNumber class]] && [pixelHeight isKindOfClass:[NSNumber class]]  && [pixelWidth isEqualToNumber:targetDimension] && [pixelHeight isEqualToNumber:targetDimension]) {
                        
                        // Use /tmp rather than NSTemporaryDirectory() or SUFileManager's temp directory function because we want:
                        // a) no spaces in the path (SU/NSFileManager fails here)
                        // b) short file path that does not exceed a small threshold (NSTemporaryDirectory() fails here)
                        // These limitations only apply to older systems (eg: macOS 10.8)
                        // The file also needs to be placed in a system readable place such as /tmp
                        // See https://github.com/sparkle-project/Sparkle/issues/347#issuecomment-149523848 for more info
                        char pathBuffer[] = "/tmp/XXXXXX.png";
                        int tempIconFile = mkstemps(pathBuffer, strlen(".png"));
                        if (tempIconFile == -1) {
                            SULog(@"Failed to open temp icon from path buffer with error: %d", errno);
                        } else {
                            close(tempIconFile);
                            
                            NSString *path = [[NSString alloc] initWithUTF8String:pathBuffer];
                            tempIconDestinationURL = [NSURL fileURLWithPath:path];
                            
                            CGImageDestinationRef imageDestination = CGImageDestinationCreateWithURL((CFURLRef)tempIconDestinationURL, kUTTypePNG, 1, NULL);
                            if (imageDestination != NULL) {
                                CGImageDestinationAddImageFromSource(imageDestination, imageSource, imageIndex, (CFDictionaryRef)@{});
                                if (CGImageDestinationFinalize(imageDestination)) {
                                    iconAuthorizationItem.valueLength = strlen(pathBuffer);
                                    iconAuthorizationItem.value = pathBuffer;
                                    
                                    authorizationEnvironment.count = 1;
                                    authorizationEnvironment.items = &iconAuthorizationItem;
                                }
                                
                                CFRelease(imageDestination);
                            }
                        }
                        
                        break;
                    }
                }
                
                CFRelease(imageSource);
            }
        }
        
        // This should prompt up the authorization dialog if necessary
        OSStatus copyStatus = AuthorizationCopyRights(auth, &rights, &authorizationEnvironment, flags, NULL);
        if (copyStatus != errAuthorizationSuccess) {
            failedToUseSystemDomain = YES;
            
            if (copyStatus == errAuthorizationCanceled) {
                canceledAuthorization = YES;
            } else {
                SULog(@"Failed copying system domain rights: %d", copyStatus);
            }
        }
        
        if (tempIconDestinationURL != nil) {
            [fileManager removeItemAtURL:tempIconDestinationURL error:NULL];
        }
    }
    
    Boolean submittedJob = false;
    if (!canceledAuthorization && !failedToUseSystemDomain && auth != NULL) {
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
                    SULog(@"Remove job error: %@", removeError);
                }
                CFRelease(removeError);
            }
        }
        
        NSDictionary *jobDictionary = @{@"Label" : label, @"ProgramArguments" : arguments, @"EnableTransactions" : @NO, @"KeepAlive" : @{@"SuccessfulExit" : @NO}, @"RunAtLoad" : @NO, @"NICE" : @0, @"LaunchOnlyOnce": @YES, @"MachServices" : @{SUInstallerServiceNameForBundleIdentifier(hostBundleIdentifier) : @YES, SUProgressAgentServiceNameForBundleIdentifier(hostBundleIdentifier) : @YES}};
        
        CFErrorRef submitError = NULL;
        submittedJob = SMJobSubmit(domain, (__bridge CFDictionaryRef)(jobDictionary), auth, &submitError);
        if (!submittedJob) {
            if (submitError != NULL) {
                SULog(@"Submit error: %@", submitError);
                CFRelease(submitError);
            }
        }
    }
    
    if (auth != NULL) {
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

- (void)launchInstallerAtPath:(NSString *)installerPath progressToolPath:(NSString *)progressToolPath withHostBundlePath:(NSString *)hostBundlePath authorizationPrompt:(NSString *)authorizationPrompt guidedInstallation:(BOOL)guidedInstallation allowingInteraction:(BOOL)allowingInteraction completion:(void (^)(SUAuthorizationReply))completionHandler
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSBundle *hostBundle = [NSBundle bundleWithPath:hostBundlePath];
        
        BOOL preflighted = NO;
        BOOL needsSystemAuthorization = SUNeedsSystemAuthorizationAccess(hostBundlePath, guidedInstallation, &preflighted);
        
        // if we need to use the system domain and we aren't already root and we aren't allowed interaction, then try sometime later when interaction is allowed
        if (needsSystemAuthorization && !preflighted && !allowingInteraction) {
            completionHandler(SUAuthorizationReplyAuthorizeLater);
        } else {
            SUAuthorizationReply installerReply = [self submitInstallerAtPath:installerPath withHostBundle:hostBundle authorizationPrompt:authorizationPrompt allowingInteraction:allowingInteraction inSystemDomain:needsSystemAuthorization];
            
            if (installerReply == SUAuthorizationReplyFailure) {
                SULog(@"Failed to submit installer job");
            }
            
            BOOL submittedProgressTool = NO;
            if (installerReply == SUAuthorizationReplySuccess) {
                submittedProgressTool = [self submitProgressToolAtPath:progressToolPath withHostBundle:hostBundle inSystemDomainForInstaller:needsSystemAuthorization];
                
                if (!submittedProgressTool) {
                    SULog(@"Failed to submit progress tool job");
                }
            }
            
            if (installerReply == SUAuthorizationReplyCancelled) {
                completionHandler(installerReply);
            } else {
                completionHandler(submittedProgressTool ? SUAuthorizationReplySuccess : SUAuthorizationReplyFailure);
            }
        }
    });
}

@end
