//
//  SUBasicUpdateDriver.m
//  Sparkle
//
//  Created by Andy Matuschak on 4/23/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUBasicUpdateDriver.h"
#import "SUUpdaterDelegate.h"
#import "SUUserDriver.h"
#import "SUHost.h"
#import "SUOperatingSystem.h"
#import "SUStandardVersionComparator.h"
#import "SUConstants.h"
#import "SULog.h"
#import "SUBinaryDeltaCommon.h"
#import "SUFileManager.h"
#import "SUErrors.h"
#import "SULocalizations.h"
#import "SUAppcastItem.h"
#import "SULocalMessagePort.h"
#import "SURemoteMessagePort.h"
#import "SUMessageTypes.h"
#import "SUAppcast.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

@interface SUBasicUpdateDriver ()

@property (strong) SUAppcastItem *updateItem;
@property (strong) NSURLDownload *download;
@property (copy) NSString *downloadPath;

@property (strong) SUAppcastItem *nonDeltaUpdateItem;
@property (copy) NSString *tempDir;

@property (nonatomic) BOOL postponedOnce;

@property (nonatomic) SULocalMessagePort *localPort;
@property (nonatomic) SURemoteMessagePort *remotePort;

@property (nonatomic) SUInstallerMessageType currentStage;

@end

@implementation SUBasicUpdateDriver

@synthesize updateItem;
@synthesize download;
@synthesize downloadPath;

@synthesize nonDeltaUpdateItem;
@synthesize tempDir;

@synthesize postponedOnce;

@synthesize localPort = _localPort;
@synthesize remotePort = _remotePort;
@synthesize currentStage = _currentStage;

- (void)checkForUpdatesAtURL:(NSURL *)URL
{
    [super checkForUpdatesAtURL:URL];
	if ([self.host isRunningOnReadOnlyVolume])
	{
        [self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SURunningFromDiskImageError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:SULocalizedString(@"%1$@ can't be updated when it's running from a read-only volume like a disk image or an optical drive. Move %1$@ to your Applications folder, relaunch it from there, and try again.", nil), [self.host name]] }]];
        return;
    }

    SUAppcast *appcast = [[SUAppcast alloc] init];

    [appcast setUserAgentString:[self.updater userAgentString]];
    [appcast setHttpHeaders:[self.updater httpHeaders]];
    [appcast fetchAppcastFromURL:URL completionBlock:^(NSError *error) {
        if (error) {
            [self abortUpdateWithError:error];
        } else {
            [self appcastDidFinishLoading:appcast];
        }
    }];
}

- (id<SUVersionComparison>)versionComparator
{
    id<SUVersionComparison> comparator = nil;

    // Give the delegate a chance to provide a custom version comparator
    if ([self.updaterDelegate respondsToSelector:@selector(versionComparatorForUpdater:)]) {
        comparator = [self.updaterDelegate versionComparatorForUpdater:self.updater];
    }

    // If we don't get a comparator from the delegate, use the default comparator
    if (!comparator) {
        comparator = [SUStandardVersionComparator defaultComparator];
    }

    return comparator;
}

+ (SUAppcastItem *)bestItemFromAppcastItems:(NSArray *)appcastItems getDeltaItem:(SUAppcastItem * __autoreleasing *)deltaItem withHostVersion:(NSString *)hostVersion comparator:(id<SUVersionComparison>)comparator
{
    SUAppcastItem *item = nil;
    for(SUAppcastItem *candidate in appcastItems) {
        if ([[self class] hostSupportsItem:candidate]) {
            if (!item || [comparator compareVersion:item.versionString toVersion:candidate.versionString] == NSOrderedAscending) {
                item = candidate;
            }
        }
    }
    
    if (item && deltaItem) {
        SUAppcastItem *deltaUpdateItem = [item deltaUpdates][hostVersion];
        if (deltaUpdateItem && [[self class] hostSupportsItem:deltaUpdateItem]) {
            *deltaItem = deltaUpdateItem;
        }
    }
    
    return item;
}

+ (BOOL)hostSupportsItem:(SUAppcastItem *)ui
{
	if (([ui minimumSystemVersion] == nil || [[ui minimumSystemVersion] isEqualToString:@""]) &&
        ([ui maximumSystemVersion] == nil || [[ui maximumSystemVersion] isEqualToString:@""])) { return YES; }

    BOOL minimumVersionOK = TRUE;
    BOOL maximumVersionOK = TRUE;

    // Check minimum and maximum System Version
    if ([ui minimumSystemVersion] != nil && ![[ui minimumSystemVersion] isEqualToString:@""]) {
        minimumVersionOK = [[SUStandardVersionComparator defaultComparator] compareVersion:[ui minimumSystemVersion] toVersion:[SUOperatingSystem systemVersionString]] != NSOrderedDescending;
    }
    if ([ui maximumSystemVersion] != nil && ![[ui maximumSystemVersion] isEqualToString:@""]) {
        maximumVersionOK = [[SUStandardVersionComparator defaultComparator] compareVersion:[ui maximumSystemVersion] toVersion:[SUOperatingSystem systemVersionString]] != NSOrderedAscending;
    }

    return minimumVersionOK && maximumVersionOK;
}

- (BOOL)isItemNewer:(SUAppcastItem *)ui
{
    return [[self versionComparator] compareVersion:[self.host version] toVersion:[ui versionString]] == NSOrderedAscending;
}

- (BOOL)itemContainsSkippedVersion:(SUAppcastItem *)ui
{
    NSString *skippedVersion = [self.host objectForUserDefaultsKey:SUSkippedVersionKey];
	if (skippedVersion == nil) { return NO; }
    return [[self versionComparator] compareVersion:[ui versionString] toVersion:skippedVersion] != NSOrderedDescending;
}

- (BOOL)itemContainsValidUpdate:(SUAppcastItem *)ui
{
    return ui && [[self class] hostSupportsItem:ui] && [self isItemNewer:ui] && ![self itemContainsSkippedVersion:ui];
}

- (void)appcastDidFinishLoading:(SUAppcast *)ac
{
    if ([self.updaterDelegate respondsToSelector:@selector(updater:didFinishLoadingAppcast:)]) {
        [self.updaterDelegate updater:self.updater didFinishLoadingAppcast:ac];
    }

    NSDictionary *userInfo = (ac != nil) ? @{ SUUpdaterAppcastNotificationKey: ac } : nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterDidFinishLoadingAppCastNotification object:self.updater userInfo:userInfo];

    SUAppcastItem *item = nil;

    // Now we have to find the best valid update in the appcast.
    if ([self.updaterDelegate respondsToSelector:@selector(bestValidUpdateInAppcast:forUpdater:)]) // Does the delegate want to handle it?
    {
        item = [self.updaterDelegate bestValidUpdateInAppcast:ac forUpdater:self.updater];
        if ([item isDeltaUpdate]) {
            self.nonDeltaUpdateItem = [self.updaterDelegate bestValidUpdateInAppcast:[ac copyWithoutDeltaUpdates] forUpdater:self.updater];
        }
	}
	else // If not, we'll take care of it ourselves.
    {
        // Find the best supported update
        SUAppcastItem *deltaUpdateItem = nil;
        item = [[self class] bestItemFromAppcastItems:ac.items getDeltaItem:&deltaUpdateItem withHostVersion:self.host.version comparator:[self versionComparator]];
        
        if (item && deltaUpdateItem) {
            self.nonDeltaUpdateItem = item;
            item = deltaUpdateItem;
        }
    }

    if ([self itemContainsValidUpdate:item]) {
        self.updateItem = item;
        [self didFindValidUpdate];
    } else {
        self.updateItem = nil;
        [self didNotFindUpdate];
    }
}

- (void)didFindValidUpdate
{
    assert(self.updateItem);

    if ([self.updaterDelegate respondsToSelector:@selector(updater:didFindValidUpdate:)]) {
        [self.updaterDelegate updater:self.updater didFindValidUpdate:self.updateItem];
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterDidFindValidUpdateNotification
                                                        object:self.updater
                                                      userInfo:@{ SUUpdaterAppcastItemNotificationKey: self.updateItem }];
    [self downloadUpdate];
}

- (void)didNotFindUpdate
{
    if ([self.updaterDelegate respondsToSelector:@selector(updaterDidNotFindUpdate:)]) {
        [self.updaterDelegate updaterDidNotFindUpdate:self.updater];
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterDidNotFindUpdateNotification object:self.updater];

    [self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain
                                                   code:SUNoUpdateError
                                               userInfo:@{
                                                   NSLocalizedDescriptionKey: [NSString stringWithFormat:SULocalizedString(@"You already have the newest version of %@.", "'Error' message when the user checks for updates but is already current or the feed doesn't contain any updates. (not necessarily shown in UI)"), self.host.name]
                                               }]];
}

- (void)downloadUpdate
{
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[self.updateItem fileURL]];
    [request setValue:[self.updater userAgentString] forHTTPHeaderField:@"User-Agent"];
    if ([self.updaterDelegate respondsToSelector:@selector(updater:willDownloadUpdate:withRequest:)]) {
        [self.updaterDelegate updater:self.updater
                      willDownloadUpdate:self.updateItem
                             withRequest:request];
    }
    self.download = [[NSURLDownload alloc] initWithRequest:request delegate:self];
}

- (void)download:(NSURLDownload *)__unused d decideDestinationWithSuggestedFilename:(NSString *)name
{
    NSString *downloadFileName = [NSString stringWithFormat:@"%@ %@", [self.host name], [self.updateItem versionString]];


    NSString *cachePath = [self.host appCachePath];
    self.tempDir = [cachePath stringByAppendingPathComponent:downloadFileName];
    int cnt = 1;
	while ([[NSFileManager defaultManager] fileExistsAtPath:self.tempDir] && cnt <= 999)
	{
        self.tempDir = [cachePath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@ %d", downloadFileName, cnt++]];
    }

    // Create the temporary directory if necessary.
    BOOL success = [[NSFileManager defaultManager] createDirectoryAtPath:self.tempDir withIntermediateDirectories:YES attributes:nil error:NULL];
	if (!success)
	{
        // Okay, something's really broken with this user's file structure.
        [self.download cancel];
        self.download = nil;
        
        [self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUTemporaryDirectoryError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Can't make a temporary directory for the update download at %@.", self.tempDir] }]];
    } else {
        self.downloadPath = [self.tempDir stringByAppendingPathComponent:name];
        [self.download setDestination:self.downloadPath allowOverwrite:YES];
    }
}

- (void)downloadDidFinish:(NSURLDownload *)__unused d
{
    assert(self.updateItem);

    if (self.download != nil && self.downloadPath != nil) {
        self.download = nil;
        [self extractUpdate];
    }
}

- (void)download:(NSURLDownload *)__unused download didFailWithError:(NSError *)error
{
    NSURL *failingUrl = error.userInfo[NSURLErrorFailingURLErrorKey];
    if (!failingUrl) {
        failingUrl = [self.updateItem fileURL];
    }

    if ([self.updaterDelegate respondsToSelector:@selector(updater:failedToDownloadUpdate:error:)]) {
        [self.updaterDelegate updater:self.updater
                  failedToDownloadUpdate:self.updateItem
                                   error:error];
    }

    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:@{
        NSLocalizedDescriptionKey: SULocalizedString(@"An error occurred while downloading the update. Please try again later.", nil),
        NSUnderlyingErrorKey: error,
    }];
    if (failingUrl) {
        userInfo[NSURLErrorFailingURLErrorKey] = failingUrl;
    }

    [self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUDownloadError userInfo:userInfo]];
}

- (BOOL)download:(NSURLDownload *)__unused download shouldDecodeSourceDataOfMIMEType:(NSString *)encodingType
{
    // We don't want the download system to extract our gzips.
    // Note that we use a substring matching here instead of direct comparison because the docs say "application/gzip" but the system *uses* "application/x-gzip". This is a documentation bug.
    return ([encodingType rangeOfString:@"gzip"].location == NSNotFound);
}

- (void)unarchiverExtractedProgress:(double)__unused progress {}

- (void)installerDidStart {}

- (void)installerIsReadyForRelaunch {}

- (void)handleMessageWithIdentifier:(int32_t)identifier data:(NSData *)data
{
    if (!SUInstallerMessageTypeIsLegal(self.currentStage, identifier)) {
        SULog(@"Error: received out of order message with current stage: %d, requested stage: %d", self.currentStage, identifier);
        return;
    }
    
    if (identifier == SUExtractedArchiveWithProgress) {
        if (data.length == sizeof(double)) {
            double progress = *(const double *)data.bytes;
            [self unarchiverExtractedProgress:progress];
            self.currentStage = identifier;
        }
    } else if (identifier == SUArchiveExtractionFailed) {
        if ([self.updateItem isDeltaUpdate]) {
            [self failedToApplyDeltaUpdate];
            return;
        }
        
        // Don't have to store current stage because we're going to abort
        
        [self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUUnarchivingError userInfo:@{ NSLocalizedDescriptionKey: SULocalizedString(@"An error occurred while extracting the archive. Please try again later.", nil) }]];
        
    } else if (identifier == SUValidationStarted) {
        self.currentStage = identifier;
    } else if (identifier == SUInstallationStartedStage1) {
        self.currentStage = identifier;
        [self installerDidStart];
        
    } else if (identifier == SUInstallationFinishedStage1) {
        self.remotePort = [[SURemoteMessagePort alloc] initWithServiceName:SUAutoUpdateServiceNameForHost(self.host) invalidationCallback:^{
            dispatch_async(dispatch_get_main_queue(), ^{
#warning put in a custom error for connection closed
                if (self.remotePort != nil) {
                    [self abortUpdate];
                }
            });
        }];
        
        if (self.remotePort == nil) {
#warning put in a custom error
            [self abortUpdate];
        } else {
            self.currentStage = identifier;
            [self installerIsReadyForRelaunch];
        }
    } else if (identifier == SUInstallationFinishedStage2) {
        // Don't have to store current stage because we're severing our connection to the installer
        
        [self.remotePort invalidate];
        self.remotePort = nil;
        
        [self.localPort invalidate];
        self.localPort = nil;
        
        [self terminateApp];
    }
}

- (void)extractUpdate
{
    self.localPort =
    [[SULocalMessagePort alloc]
     initWithServiceName:SUUpdateDriverServiceNameForHost(self.host)
     messageCallback:^(int32_t identifier, NSData * _Nonnull data) {
         dispatch_async(dispatch_get_main_queue(), ^{
             [self handleMessageWithIdentifier:identifier data:data];
         });
     }
     invalidationCallback:^{
         dispatch_async(dispatch_get_main_queue(), ^{
             if (self.localPort != nil) {
#warning use a custom error
                 [self abortUpdate];
             }
         });
     }];
    
    if (self.localPort == nil) {
#warning use a custom error
        [self abortUpdate];
    } else {
        NSError *error = nil;
        if (![self launchAutoUpdate:&error]) {
            [self abortUpdateWithError:error];
        } else {
            // Autoupdate takes ownership of cleaning up our temporary download directory now
            self.tempDir = nil;
        }
    }
}

- (void)failedToApplyDeltaUpdate
{
    // When a delta update fails to apply we fall back on updating via a full install.
    self.updateItem = self.nonDeltaUpdateItem;
    self.nonDeltaUpdateItem = nil;

    [self downloadUpdate];
}

- (void)installWithToolAndRelaunch:(BOOL)relaunch
{
    // Perhaps a poor assumption but: if we're not relaunching, we assume we shouldn't be showing any UI either. Because non-relaunching installations are kicked off without any user interaction, we shouldn't be interrupting them.
    [self installWithToolAndRelaunch:relaunch displayingUserInterface:relaunch];
}

// Creates intermediate directories up until targetPath if they don't already exist,
// and removes the directory at targetPath if one already exists there
- (BOOL)preparePathForRelaunchTool:(NSString *)targetPath error:(NSError * __autoreleasing *)error
{
    NSFileManager *fileManager = [[NSFileManager alloc] init];
    if ([fileManager fileExistsAtPath:targetPath]) {
        NSError *removeError = nil;
        if (![fileManager removeItemAtPath:targetPath error:&removeError]) {
            if (error != NULL) {
                *error = removeError;
            }
            return NO;
        }
    } else {
        NSError *createDirectoryError = nil;
        if (![fileManager createDirectoryAtPath:[targetPath stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:@{} error:&createDirectoryError]) {
            if (error != NULL) {
                *error = createDirectoryError;
            }
            return NO;
        }
    }
    return YES;
}

- (BOOL)launchAutoUpdate:(NSError * __autoreleasing *)outError
{
    NSBundle *sparkleBundle = self.sparkleBundle;
    
    NSString *relaunchPath = nil;
    
    // Copy the relauncher into a temporary directory so we can get to it after the new version's installed.
    // Only the paranoid survive: if there's already a stray copy of relaunch there, we would have problems.
    NSString *const relaunchToolName = @"" SPARKLE_RELAUNCH_TOOL_NAME;
    NSString *const relaunchPathToCopy = [sparkleBundle pathForResource:relaunchToolName ofType:@"app"];
    if (relaunchPathToCopy != nil) {
        NSString *targetPath = [self.host.appCachePath stringByAppendingPathComponent:[relaunchPathToCopy lastPathComponent]];
        
        SUFileManager *fileManager = [SUFileManager fileManagerAllowingAuthorization:NO];
        NSError *error = nil;
        
        NSURL *relaunchURLToCopy = [NSURL fileURLWithPath:relaunchPathToCopy];
        NSURL *targetURL = [NSURL fileURLWithPath:targetPath];
        
        // We only need to run our copy of the app by spawning a task
        // Since we are copying the app to a directory that is write-accessible, we don't need to muck with owner/group IDs
        if ([self preparePathForRelaunchTool:targetPath error:&error] && [fileManager copyItemAtURL:relaunchURLToCopy toURL:targetURL error:&error]) {
            // Releasing quarantine is definitely important (didn't used to be) now that we launch AutoUpdate via LaunchServices
            // Perhaps even if this fails, we should continue on in the hopes maybe this isn't a fatal error though
            NSError *quarantineError = nil;
            if (![fileManager releaseItemFromQuarantineAtRootURL:targetURL error:&quarantineError]) {
                SULog(@"Failed to release quarantine on %@ with error %@", targetPath, quarantineError);
            }
            relaunchPath = targetPath;
        } else {
            if (outError != NULL) {
                *outError =
                [NSError errorWithDomain:SUSparkleErrorDomain code:SURelaunchError userInfo:@{
                    NSLocalizedDescriptionKey: SULocalizedString(@"An error occurred while extracting the archive. Please try again later.", nil),
                    NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:@"Couldn't copy relauncher (%@) to temporary path (%@)! %@", relaunchPathToCopy, targetPath, (error ? [error localizedDescription] : @"")]
                }];
            }
            
            return NO;
        }
    }
    
    NSString *relaunchToolPath = [[NSBundle bundleWithPath:relaunchPath] executablePath];
    if (!relaunchToolPath || ![[NSFileManager defaultManager] fileExistsAtPath:relaunchPath]) {
        // Note that we explicitly use the host app's name here, since updating plugin for Mail relaunches Mail, not just the plugin.
        if (outError != NULL) {
            *outError =
            [NSError errorWithDomain:SUSparkleErrorDomain code:SURelaunchError userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:SULocalizedString(@"An error occurred while relaunching %1$@, but the new version will be available next time you run %1$@.", nil), [self.host name]],
                NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:@"Couldn't find the relauncher (expected to find it at %@)", relaunchPath]
            }];
        }
        
        // We intentionally don't abandon the update here so that the host won't initiate another.
        return NO;
    }
    
    NSString *pathToRelaunch = [self.host bundlePath];
    if ([self.updaterDelegate respondsToSelector:@selector(pathToRelaunchForUpdater:)]) {
        pathToRelaunch = [self.updaterDelegate pathToRelaunchForUpdater:self.updater];
    }
    
    NSString *dsaSignature = self.updateItem.DSASignature == nil ? @"" : self.updateItem.DSASignature;
    
    NSArray *launchArguments = @[
                                 pathToRelaunch,
                                 self.host.bundlePath,
                                 self.tempDir,
                                 self.downloadPath,
                                 dsaSignature,
                                 @"1"]; // last one signifies the relaunch tool should exit & reply back to us immediately
    
    // Make sure the launched task finishes & replies back.
    // If it succeeds, it will have launched a second instance of the tool through LaunchServices
    // This is necessary if we are a XPC process, because otherwise we risk exiting prematurely
    // Further, we don't launch through LS here because we don't want to reference AppKit here
    int terminationStatus = 0;
    BOOL taskDidLaunch = NO;
    @try {
        NSTask *launchedTask = [NSTask launchedTaskWithLaunchPath:relaunchToolPath arguments:launchArguments];
        [launchedTask waitUntilExit];
        taskDidLaunch = YES;
        terminationStatus = launchedTask.terminationStatus;
    } @catch (NSException *exception) {
        SULog(@"Raised exception when launching update tool: %@", exception);
    }
    
    if (!taskDidLaunch || terminationStatus != 0) {
        if (taskDidLaunch) {
            SULog(@"Update tool failed with exit code: %d", terminationStatus);
        }
        
        if (outError != NULL) {
            *outError =
            [NSError errorWithDomain:SUSparkleErrorDomain code:SURelaunchError userInfo:@{
                NSLocalizedDescriptionKey: SULocalizedString(@"An error occurred while launching the updater. Please try again later.", nil),
                NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:@"Couldn't launch relauncher at %@", relaunchToolPath]
            }];
        }
        
        return NO;
    }
    
    return YES;
}

- (BOOL)mayUpdateAndRestart
{
    return (!self.updaterDelegate || ![self.updaterDelegate respondsToSelector:@selector(updaterShouldRelaunchApplication:)] || [self.updaterDelegate updaterShouldRelaunchApplication:self.updater]);
}

- (void)installWithToolAndRelaunch:(BOOL)relaunch displayingUserInterface:(BOOL)showUI
{
    assert(self.updateItem);
    
    if (![self mayUpdateAndRestart])
    {
        [self abortUpdate];
        return;
    }
    
    // Give the host app an opportunity to postpone the install and relaunch.
    if (!self.postponedOnce && [self.updaterDelegate respondsToSelector:@selector(updater:shouldPostponeRelaunchForUpdate:untilInvoking:)])
    {
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[[self class] instanceMethodSignatureForSelector:@selector(installWithToolAndRelaunch:)]];
        [invocation setSelector:@selector(installWithToolAndRelaunch:)];
        [invocation setArgument:&relaunch atIndex:2];
        [invocation setTarget:self];
        self.postponedOnce = YES;
        if ([self.updaterDelegate updater:self.updater shouldPostponeRelaunchForUpdate:self.updateItem untilInvoking:invocation]) {
            return;
        }
    }

    if ([self.updaterDelegate respondsToSelector:@selector(updater:willInstallUpdate:)]) {
        [self.updaterDelegate updater:self.updater willInstallUpdate:self.updateItem];
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterWillRestartNotification object:self];
    if ([self.updaterDelegate respondsToSelector:@selector(updaterWillRelaunchApplication:)]) {
        [self.updaterDelegate updaterWillRelaunchApplication:self.updater];
    }
    
    uint8_t response[2] = {(uint8_t)relaunch, (uint8_t)showUI};
    NSData *responseData = [NSData dataWithBytes:response length:sizeof(response)];
    
    [self.remotePort sendMessageWithIdentifier:SUResumeInstallationToStage2 data:responseData completion:^(BOOL success) {
        if (!success) {
            dispatch_async(dispatch_get_main_queue(), ^{
#warning put in a custom error
                [self abortUpdate];
            });
        } else {
            // We'll terminate later when the installer tells us stage 2 is done
        }
    }];
}

// Note: this is overridden by the automatic update driver to do nothing
- (void)terminateApp
{
    [self.userDriver terminateApplication];
}

- (void)cleanUpDownload
{
    if (self.tempDir != nil) // tempDir contains downloadPath, so we implicitly delete both here.
    {
        BOOL success = NO;
        NSError *error = nil;
        success = [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:&error]; // Clean up the copied relauncher
        if (!success) {
            NSURL *tempDirURL = [NSURL fileURLWithPath:self.tempDir];
            if (tempDirURL != nil) {
                [[SUFileManager fileManagerAllowingAuthorization:NO] moveItemAtURLToTrash:tempDirURL error:NULL];
            }
        }
    }
    
    if (self.download != nil) {
        [self.download cancel];
        self.download = nil;
    }
    self.downloadPath = nil;
}

- (void)abortUpdate
{
    if (self.localPort != nil) {
        [self.localPort invalidate];
        self.localPort = nil;
    }
    
    if (self.remotePort != nil) {
        [self.remotePort invalidate];
        self.remotePort = nil;
    }
    
    [self.userDriver dismissUpdateInstallation];
    
    [self cleanUpDownload];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    self.updateItem = nil;
    [super abortUpdate];
}

- (void)abortUpdateWithError:(NSError *)error
{
    if ([error code] != SUNoUpdateError) { // Let's not bother logging this.
        NSError *errorToDisplay = error;
        int finiteRecursion=5;
        do {
            SULog(@"Error: %@ %@ (URL %@)", errorToDisplay.localizedDescription, errorToDisplay.localizedFailureReason, errorToDisplay.userInfo[NSURLErrorFailingURLErrorKey]);
            errorToDisplay = errorToDisplay.userInfo[NSUnderlyingErrorKey];
        } while(--finiteRecursion && errorToDisplay);
    }

    // Notify host app that update has aborted
    if ([self.updaterDelegate respondsToSelector:@selector(updater:didAbortWithError:)]) {
        [self.updaterDelegate updater:self.updater didAbortWithError:error];
    }

    [self abortUpdate];
}

@end
