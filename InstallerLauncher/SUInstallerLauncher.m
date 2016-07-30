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
#import "SULocalCacheDirectory.h"
#import "SUInstallationType.h"
#import <ServiceManagement/ServiceManagement.h>

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
    
    // The progress tool can only be ran as the logged in user, not as root
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

- (SUInstallerLauncherStatus)submitInstallerAtPath:(NSString *)installerPath withHostBundle:(NSBundle *)hostBundle authorizationPrompt:(NSString *)authorizationPrompt inSystemDomain:(BOOL)systemDomain
{
    SUFileManager *fileManager = [SUFileManager defaultManager];
    
    // No need to release the quarantine for this utility
    // In fact, we shouldn't because the tool may be located at a path we should not be writing too.
    
    NSString *hostBundleIdentifier = hostBundle.bundleIdentifier;
    assert(hostBundleIdentifier != nil);
    
    // The first argument has to be the path to the program, and the second is a host identifier so that the installer knows what mach services to host
    // We intentionally do not pass any more arguments. Anything else should be done via IPC.
    // This is compatible to SMJobBless() which does not allow arguments
    // Even though we aren't using that function for now, it'd be wise to not decrease compatibility to it
    NSArray<NSString *> *arguments = @[installerPath, hostBundleIdentifier];
    
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
        
        NSDictionary *jobDictionary = @{@"Label" : label, @"ProgramArguments" : arguments, @"EnableTransactions" : @NO, @"KeepAlive" : @{@"SuccessfulExit" : @NO}, @"RunAtLoad" : @NO, @"Nice" : @0, @"LaunchOnlyOnce": @YES, @"MachServices" : @{SUInstallerServiceNameForBundleIdentifier(hostBundleIdentifier) : @YES, SUProgressAgentServiceNameForBundleIdentifier(hostBundleIdentifier) : @YES}};
        
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
    
    SUInstallerLauncherStatus status;
    if (submittedJob == true) {
        status = SUInstallerLauncherSuccess;
    } else if (canceledAuthorization) {
        status = SUInstallerLauncherCanceled;
    } else {
        status = SUInstallerLauncherFailure;
    }
    return status;
}

// First we check if the tool is in an auxiliary directory. If that fails, we then check if it is in a resources directory
- (NSString *)pathForBundledTool:(NSString *)toolName extension:(NSString *)extension inBundle:(NSBundle *)bundle
{
    NSString *resultPath = nil;
    // If the path extension is empty, we don't want to add a "." at the end
    NSString *pathWithExtension = (extension.length > 0) ? [toolName stringByAppendingPathExtension:extension] : toolName;
    assert(pathWithExtension != nil);
    NSString *auxiliaryPath = [bundle pathForAuxiliaryExecutable:pathWithExtension];
    if (auxiliaryPath == nil || ![[NSFileManager defaultManager] fileExistsAtPath:auxiliaryPath]) {
        resultPath = [bundle pathForResource:toolName ofType:extension];
    } else {
        resultPath = auxiliaryPath;
    }
    return resultPath;
}

// Note: do not pass untrusted information such as paths to the installer and progress agent tools, when we can find them ourselves here
- (void)launchInstallerWithHostBundlePath:(NSString *)hostBundlePath authorizationPrompt:(NSString *)authorizationPrompt installationType:(NSString *)installationType allowingDriverInteraction:(BOOL)allowingDriverInteraction allowingUpdaterInteraction:(BOOL)allowingUpdaterInteraction completion:(void (^)(SUInstallerLauncherStatus))completionHandler
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSBundle *hostBundle = [NSBundle bundleWithPath:hostBundlePath];
        BOOL needsSystemAuthorization = SUNeedsSystemAuthorizationAccess(hostBundlePath, installationType);
        
        if (needsSystemAuthorization && !allowingUpdaterInteraction) {
            SULog(@"Updater is not allowing interaction to the launcher.");
            completionHandler(SUInstallerLauncherFailure);
            return;
        }
        
        if (!allowingUpdaterInteraction && [installationType isEqualToString:SUInstallationTypeInteractivePackage]) {
            SULog(@"Updater is not allowing interaction to the launcher for performing an interactive type package installation.");
            completionHandler(SUInstallerLauncherFailure);
            return;
        }
        
        // if we need to use the system domain and we aren't allowed interaction, then try sometime later when interaction is allowed
        if (needsSystemAuthorization && !allowingDriverInteraction) {
            completionHandler(SUInstallerLauncherAuthorizeLater);
            return;
        }
        
        NSString *hostBundleIdentifier = hostBundle.bundleIdentifier;
        assert(hostBundleIdentifier != nil);
        
        // We could be inside the InstallerLauncher XPC bundle or in the Sparkle.framework bundle if no XPC service is used
        NSBundle *ourBundle = [NSBundle bundleForClass:[self class]];
        
        // Note we do not have to copy this tool out of the bundle it's in because it's a utility with no dependencies.
        // Furthermore, we can keep the tool at a place that may not necessarily be writable.
        NSString *installerPath = [self pathForBundledTool:@""SPARKLE_RELAUNCH_TOOL_NAME extension:@"" inBundle:ourBundle];
        if (installerPath == nil) {
            SULog(@"Error: Cannot submit installer because the installer could not be located");
            completionHandler(SUInstallerLauncherFailure);
            return;
        }
        
        // We do however have to copy the progress tool app somewhere safe due to its external depedencies
        NSString *progressToolResourcePath = [self pathForBundledTool:@""SPARKLE_INSTALLER_PROGRESS_TOOL_NAME extension:@"app" inBundle:ourBundle];
        
        if (progressToolResourcePath == nil) {
            SULog(@"Error: Cannot submit progress tool because the progress tool could not be located");
            completionHandler(SUInstallerLauncherFailure);
            return;
        }
        
        // It may be tempting here to validate/match the signature of the installer and progress tool, however this is not very reliable
        // We can't compare the signature of this framework/XPC service (depending how it's run) to the host bundle because
        // they could be different (eg: take a look at sparkle-cli). We also can't easily tell if the signature of the service/framework is the same as the bundle it's inside.
        // The service/framework also need not even be signed in the first place. We'll just assume for now the original bundle hasn't been tampered with
        
        NSString *launcherCachePath = [[SULocalCacheDirectory cachePathForBundleIdentifier:hostBundleIdentifier] stringByAppendingPathComponent:@"Launcher"];
        
        NSFileManager *fileManager = [NSFileManager defaultManager];
        [fileManager removeItemAtPath:launcherCachePath error:NULL];
        
        NSError *createCacheError = nil;
        if (![fileManager createDirectoryAtPath:launcherCachePath withIntermediateDirectories:YES attributes:nil error:&createCacheError]) {
            SULog(@"Failed to create cache directory for progress tool: %@", createCacheError);
            completionHandler(SUInstallerLauncherFailure);
            return;
        }
        
        NSString *progressToolPath = [launcherCachePath stringByAppendingPathComponent:@""SPARKLE_INSTALLER_PROGRESS_TOOL_NAME@".app"];
        
        NSError *copyError = nil;
        // SUFileManager is more reliable for copying files around
        if (![[SUFileManager defaultManager] copyItemAtURL:[NSURL fileURLWithPath:progressToolResourcePath] toURL:[NSURL fileURLWithPath:progressToolPath] error:&copyError]) {
            SULog(@"Failed to copy progress tool to cache: %@", copyError);
            completionHandler(SUInstallerLauncherFailure);
            return;
        }
        
        SUInstallerLauncherStatus installerStatus = [self submitInstallerAtPath:installerPath withHostBundle:hostBundle authorizationPrompt:authorizationPrompt inSystemDomain:needsSystemAuthorization];
        
        BOOL submittedProgressTool = NO;
        if (installerStatus == SUInstallerLauncherSuccess) {
            submittedProgressTool = [self submitProgressToolAtPath:progressToolPath withHostBundle:hostBundle inSystemDomainForInstaller:needsSystemAuthorization];
            
            if (!submittedProgressTool) {
                SULog(@"Failed to submit progress tool job");
            }
        } else if (installerStatus == SUInstallerLauncherFailure) {
            SULog(@"Failed to submit installer job");
        }
        
        if (installerStatus == SUInstallerLauncherCanceled) {
            completionHandler(installerStatus);
        } else {
            completionHandler(submittedProgressTool ? SUInstallerLauncherSuccess : SUInstallerLauncherFailure);
        }
    });
}

@end
