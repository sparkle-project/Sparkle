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
#import "SUInstallerProgressLauncherProtocol.h"

#define AUTHORIZATION_REPLY_TIMEOUT 7ull

@interface SUInstallerLauncher ()

@property (nonatomic, nullable) NSXPCConnection *activeConnection;

@end

@implementation SUInstallerLauncher

@synthesize activeConnection = _activeConnection;

- (BOOL)submitProgressToolAtPath:(NSString *)progressToolPath withHostBundle:(NSBundle *)hostBundle allowingInteraction:(BOOL)allowingInteraction  installerPath:(NSString *)installerPath shouldSubmitInstaller:(BOOL)shouldSubmitInstaller
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
    
    NSArray<NSString *> *arguments = @[executablePath, hostBundlePath, @(allowingInteraction).stringValue, installerPath, @(shouldSubmitInstaller).stringValue];
    
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
        
        if (shouldSubmitInstaller) {
            jobDictionary[@"MachServices"] = @{SUProgressAgentLauncherServiceNameForBundleIdentifier(hostBundleIdentifier) : @YES};
        }
        
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

- (void)waitForProgressAgentWithHostBundle:(NSBundle *)hostBundle completion:(void (^)(SUAuthorizationReply))completionHandler
{
    NSString *hostBundleIdentifier = hostBundle.bundleIdentifier;
    assert(hostBundleIdentifier != nil);
    
    NSXPCConnection *connection = [[NSXPCConnection alloc] initWithMachServiceName:SUProgressAgentLauncherServiceNameForBundleIdentifier(hostBundleIdentifier) options:(NSXPCConnectionOptions)0];
    
    connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUInstallerProgressLauncherProtocol)];
    
    self.activeConnection = connection;
    
    __weak SUInstallerLauncher *weakSelf = self;
    connection.interruptionHandler = ^{
        [weakSelf.activeConnection invalidate];
    };
    
    __block BOOL invokedCompletion = NO;
    
    connection.invalidationHandler = ^{
       dispatch_async(dispatch_get_main_queue(), ^{
           if (!invokedCompletion) {
               invokedCompletion = YES;
               completionHandler(SUAuthorizationReplyFailure);
           }
       });
    };
    
    [connection resume];
    
    id<SUInstallerProgressLauncherProtocol> launcher = connection.remoteObjectProxy;
    
    __block BOOL intiatedConnection = NO;
    [launcher connectionDidInitiateWithReply:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            intiatedConnection = YES;
            
            [launcher requestUserAuthorizationWithReply:^(SUAuthorizationReply reply) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (!invokedCompletion) {
                        invokedCompletion = YES;
                        [weakSelf.activeConnection invalidate];
                        completionHandler(reply);
                    }
                });
            }];
        });
    }];
    
    // If we initiated a connection, we can't time out because the user could just be taking a really long time to reply
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(AUTHORIZATION_REPLY_TIMEOUT * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!intiatedConnection && !invokedCompletion) {
            [weakSelf.activeConnection invalidate];
        }
    });
}

- (void)launchInstallerAtPath:(NSString *)installerPath progressToolPath:(NSString *)progressToolPath withHostBundlePath:(NSString *)hostBundlePath guidedInstallation:(BOOL)guidedInstallation allowingInteraction:(BOOL)allowingInteraction completion:(void (^)(SUAuthorizationReply))completionHandler
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSBundle *hostBundle = [NSBundle bundleWithPath:hostBundlePath];
        
        BOOL submittedInstaller = NO;
        BOOL preflighted = NO;
        
        // Only submit a job here if we are preflighted (already running root in which case we use system domain),
        // or if we do not have to ask the user for authorization
        BOOL needsSystemAuthorization = SUNeedsSystemAuthorizationAccess(hostBundlePath, guidedInstallation, &preflighted);
        BOOL shouldSubmitInstallerImmediately = (!needsSystemAuthorization || preflighted);
        if (shouldSubmitInstallerImmediately) {
            submittedInstaller = ([SUSubmitInstaller submitInstallerAtPath:installerPath withHostBundle:hostBundle allowingInteraction:allowingInteraction inSystemDomain:needsSystemAuthorization] == SUAuthorizationReplySuccess);
        }
        
        BOOL submittedProgressTool = [self submitProgressToolAtPath:progressToolPath withHostBundle:hostBundle allowingInteraction:allowingInteraction  installerPath:installerPath shouldSubmitInstaller:!shouldSubmitInstallerImmediately];
        
        if (!submittedProgressTool) {
            completionHandler(SUAuthorizationReplyFailure);
        } else if (shouldSubmitInstallerImmediately) {
            completionHandler(submittedInstaller ? SUAuthorizationReplySuccess : SUAuthorizationReplyFailure);
        } else {
            [self waitForProgressAgentWithHostBundle:hostBundle completion:completionHandler];
        }
    });
}

@end
