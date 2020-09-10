//
//  SUBasicUpdateDriver.m
//  Sparkle
//
//  Created by Andy Matuschak on 4/23/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUBasicUpdateDriver.h"

#import "SUUnarchiverProtocol.h"
#import "SUHost.h"
#import "SUOperatingSystem.h"
#import "SUStandardVersionComparator.h"
#import "SUUnarchiver.h"
#import "SUConstants.h"
#import "SULog.h"
#import "SUBinaryDeltaCommon.h"
#import "SUUpdaterPrivate.h"
#import "SUUpdaterDelegate.h"
#import "SUFileManager.h"
#import "SUUpdateValidator.h"
#import "SULocalizations.h"
#import "SUErrors.h"
#import "SUUpdater.h"
#import "SUAppcast.h"
#import "SUAppcastItem.h"

#import "SPUURLRequest.h"
#import "SPUDownloaderDeprecated.h"
#import "SPUDownloaderSession.h"

@interface SUBasicUpdateDriver ()

@property (strong) SUAppcastItem *updateItem;
@property (strong) SUAppcastItem *latestAppcastItem;
@property (assign) NSComparisonResult latestAppcastItemComparisonResult;
@property (strong) SPUDownloader *download;
@property (copy) NSString *downloadPath;

@property (strong) SUAppcastItem *nonDeltaUpdateItem;
@property (copy) NSString *tempDir;
@property (copy) NSString *relaunchPath;

@property (nonatomic) SUUpdateValidator *updateValidator;

@end

@implementation SUBasicUpdateDriver

@synthesize updateItem;
@synthesize latestAppcastItem;
@synthesize latestAppcastItemComparisonResult;
@synthesize download;
@synthesize downloadPath;

@synthesize nonDeltaUpdateItem;
@synthesize tempDir;
@synthesize relaunchPath;

@synthesize updateValidator = _updateValidator;

- (void)checkForUpdatesAtURL:(NSURL *)URL host:(SUHost *)aHost
{
    [super checkForUpdatesAtURL:URL host:aHost];
	if ([aHost isRunningOnReadOnlyVolume])
	{
        NSString *hostName = [aHost name];
        if ([aHost isRunningTranslocated])
        {
            [self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SURunningTranslocated userInfo:@{ NSLocalizedRecoverySuggestionErrorKey: [NSString stringWithFormat:SULocalizedString(@"Quit %1$@, move it into your Applications folder, relaunch it from there and try again.", nil), hostName], NSLocalizedDescriptionKey: [NSString stringWithFormat:SULocalizedString(@"%1$@ can’t be updated if it’s running from the location it was downloaded to.", nil), hostName], }]];
        }
        else
        {
            [self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SURunningFromDiskImageError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:SULocalizedString(@"%1$@ can't be updated, because it was opened from a read-only or a temporary location.", nil), hostName], NSLocalizedRecoverySuggestionErrorKey: [NSString stringWithFormat:SULocalizedString(@"Use Finder to copy %1$@ to the Applications folder, relaunch it from there, and try again.", nil), hostName] }]];
        }
        return;
    }

    SUAppcast *appcast = [[SUAppcast alloc] init];

    id<SUUpdaterPrivate> updater = self.updater;
    [appcast setUserAgentString:[updater userAgentString]];
    [appcast setHttpHeaders:[updater httpHeaders]];
    [appcast fetchAppcastFromURL:URL inBackground:self.downloadsAppcastInBackground completionBlock:^(NSError *error) {
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
    id<SUUpdaterPrivate> updater = self.updater;

    // Give the delegate a chance to provide a custom version comparator
    if ([[updater delegate] respondsToSelector:@selector(versionComparatorForUpdater:)]) {
        comparator = [[updater delegate] versionComparatorForUpdater:self.updater];
    }

    // If we don't get a comparator from the delegate, use the default comparator
    if (!comparator) {
        comparator = [[SUStandardVersionComparator alloc] init];
    }

    return comparator;
}

// This method is only used for testing
+ (SUAppcastItem *)bestItemFromAppcastItems:(NSArray *)appcastItems getDeltaItem:(SUAppcastItem *_Nullable __autoreleasing *_Nullable)deltaItem withHostVersion:(NSString *)hostVersion comparator:(id<SUVersionComparison>)comparator {
    SUBasicUpdateDriver* basicUpdateDriver = [[SUBasicUpdateDriver alloc] initWithUpdater:(id<SUUpdaterPrivate>)[SUUpdater sharedUpdater]];
    return [basicUpdateDriver bestItemFromAppcastItems:appcastItems getDeltaItem:deltaItem withHostVersion:hostVersion comparator:comparator];
}

- (SUAppcastItem *)bestItemFromAppcastItems:(NSArray *)appcastItems getDeltaItem:(SUAppcastItem * __autoreleasing *)deltaItem withHostVersion:(NSString *)hostVersion comparator:(id<SUVersionComparison>)comparator
{
    SUAppcastItem *item = nil;
    NSComparisonResult order;

    for(SUAppcastItem *candidate in appcastItems) {
        if ([self hostSupportsItem:candidate]) {
            // Pick this item if nothing is picked yet. Always pick an item with a higher version. Only if versions are the same
            // compare their dates and pick this item if its date is not lower – this covers cases when no date is available
            // and picks items at the end of the appcast list as they are more likely to be the most recent releases.
            if (
                !item
                    || (order = [comparator compareVersion:item.versionString toVersion:candidate.versionString]) == NSOrderedAscending
                    || (order == NSOrderedSame && [item.date compare:candidate.date] != NSOrderedDescending)
            ) {
                item = candidate;
            }
        }
    }

    if (item && deltaItem) {
        SUAppcastItem *deltaUpdateItem = [[item deltaUpdates] objectForKey:hostVersion];
        if (deltaUpdateItem && [self hostSupportsItem:deltaUpdateItem]) {
            *deltaItem = deltaUpdateItem;
        }
    }

    return item;
}

- (BOOL)hostSupportsItem:(SUAppcastItem *)ui
{
    BOOL osOK = [ui isMacOsUpdate];
	if (([ui minimumSystemVersion] == nil || [[ui minimumSystemVersion] isEqualToString:@""]) &&
        ([ui maximumSystemVersion] == nil || [[ui maximumSystemVersion] isEqualToString:@""])) {
        return osOK;
    }

    BOOL minimumVersionOK = TRUE;
    BOOL maximumVersionOK = TRUE;

    id<SUVersionComparison> versionComparator = [[SUStandardVersionComparator alloc] init];

    // Check minimum and maximum System Version
    if ([ui minimumSystemVersion] != nil && ![[ui minimumSystemVersion] isEqualToString:@""]) {
        minimumVersionOK = [versionComparator compareVersion:[ui minimumSystemVersion] toVersion:[SUOperatingSystem systemVersionString]] != NSOrderedDescending;
    }
    if ([ui maximumSystemVersion] != nil && ![[ui maximumSystemVersion] isEqualToString:@""]) {
        maximumVersionOK = [versionComparator compareVersion:[ui maximumSystemVersion] toVersion:[SUOperatingSystem systemVersionString]] != NSOrderedAscending;
    }

    return minimumVersionOK && maximumVersionOK && osOK;
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
    return ui && [self hostSupportsItem:ui] && [self isItemNewer:ui] && ![self itemContainsSkippedVersion:ui];
}

- (void)appcastDidFinishLoading:(SUAppcast *)ac
{
    id<SUUpdaterPrivate> updater = self.updater;
    if ([[updater delegate] respondsToSelector:@selector(updater:didFinishLoadingAppcast:)]) {
        [[updater delegate] updater:self.updater didFinishLoadingAppcast:ac];
    }

    NSDictionary *userInfo = @{ SUUpdaterAppcastNotificationKey: ac };
    [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterDidFinishLoadingAppCastNotification object:self.updater userInfo:userInfo];

    SUAppcastItem *item = nil;

    // Now we have to find the best valid update in the appcast.
    if ([[updater delegate] respondsToSelector:@selector(bestValidUpdateInAppcast:forUpdater:)]) // Does the delegate want to handle it?
    {
        item = [[updater delegate] bestValidUpdateInAppcast:ac forUpdater:self.updater];
    }

    if (item != nil) // Does the delegate want to handle it?
    {
        if ([item isDeltaUpdate]) {
            self.nonDeltaUpdateItem = [[updater delegate] bestValidUpdateInAppcast:[ac copyWithoutDeltaUpdates] forUpdater:self.updater];
        }
    }
    else // If not, we'll take care of it ourselves.
    {
        // Find the best supported update
        SUAppcastItem *deltaUpdateItem = nil;
        item = [self bestItemFromAppcastItems:ac.items getDeltaItem:&deltaUpdateItem withHostVersion:self.host.version comparator:[self versionComparator]];

        if (item && deltaUpdateItem) {
            self.nonDeltaUpdateItem = item;
            item = deltaUpdateItem;
        }
    }

    self.latestAppcastItem = item;
    self.latestAppcastItemComparisonResult = [[self versionComparator] compareVersion:[self.host version] toVersion:[item versionString]];


    if ([self itemContainsValidUpdate:item]) {
        self.updateItem = item;
        [self performSelectorOnMainThread:@selector(didFindValidUpdate) withObject:nil waitUntilDone:NO];
    } else {
        self.updateItem = nil;
        [self performSelectorOnMainThread:@selector(didNotFindUpdate) withObject:nil waitUntilDone:NO];
    }
}

- (void)didFindValidUpdate
{
    assert(self.updateItem);

    id<SUUpdaterPrivate> updater = self.updater;

    if ([[updater delegate] respondsToSelector:@selector(updater:didFindValidUpdate:)]) {
        [[updater delegate] updater:self.updater didFindValidUpdate:self.updateItem];
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterDidFindValidUpdateNotification
                                                        object:self.updater
                                                      userInfo:@{ SUUpdaterAppcastItemNotificationKey: self.updateItem }];
    [self downloadUpdate];
}

- (void)didNotFindUpdate
{
    id<SUUpdaterPrivate> updater = self.updater;

    if ([[updater delegate] respondsToSelector:@selector(updaterDidNotFindUpdate:)]) {
        [[updater delegate] updaterDidNotFindUpdate:self.updater];
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterDidNotFindUpdateNotification object:self.updater];

    [self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain
                                                   code:SUNoUpdateError
                                               userInfo:@{
                                                   NSLocalizedDescriptionKey: [NSString stringWithFormat:SULocalizedString(@"You already have the newest version of %@.", "'Error' message when the user checks for updates but is already current or the feed doesn't contain any updates. (not necessarily shown in UI)"), self.host.name]
                                               }]];
}

- (NSString *)appCachePath
{
    NSArray *cachePaths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cachePath = nil;
    if ([cachePaths count]) {
        cachePath = [cachePaths objectAtIndex:0];
    }
    if (!cachePath) {
        SULog(SULogLevelError, @"Failed to find user's cache directory! Using system default");
        cachePath = NSTemporaryDirectory();
    }

    NSString *name = [self.host.bundle bundleIdentifier];
    if (!name) {
        name = [self.host name];
    }

    cachePath = [cachePath stringByAppendingPathComponent:name];
    cachePath = [cachePath stringByAppendingPathComponent:@SPARKLE_BUNDLE_IDENTIFIER];
    return cachePath;
}

- (void)downloadUpdate
{
    NSString *bundleIdentifier = self.host.bundle.bundleIdentifier;
    assert(bundleIdentifier != nil);

    // Clear cache directory so that downloads can't possibly accumulate inside
    NSString *appCachePath = [self appCachePath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:appCachePath]) {
        [[NSFileManager defaultManager] removeItemAtPath:appCachePath error:NULL];
    }

    id<SUUpdaterPrivate> updater = self.updater;

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[self.updateItem fileURL]];
    if (self.downloadsUpdatesInBackground) {
        request.networkServiceType = NSURLNetworkServiceTypeBackground;
    }

    [request setValue:[updater userAgentString] forHTTPHeaderField:@"User-Agent"];
    if ([[updater delegate] respondsToSelector:@selector(updater:willDownloadUpdate:withRequest:)]) {
        [[updater delegate] updater:self.updater
                      willDownloadUpdate:self.updateItem
                             withRequest:request];
    }

    if (SUAVAILABLE(10, 9)) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability"
        self.download = [[SPUDownloaderSession alloc] initWithDelegate:self];
#pragma clang diagnostic pop
    }
    else {
        self.download = [[SPUDownloaderDeprecated alloc] initWithDelegate:self];
    }
    SPUURLRequest *urlRequest = [SPUURLRequest URLRequestWithRequest:request];
    NSString *desiredFilename = [NSString stringWithFormat:@"%@ %@", [self.host name], [self.updateItem versionString]];
    [self.download startPersistentDownloadWithRequest:urlRequest bundleIdentifier:bundleIdentifier desiredFilename:desiredFilename];
}


- (void)downloaderDidSetDestinationName:(NSString *)destinationName temporaryDirectory:(NSString *)temporaryDirectory
{
    self.tempDir = temporaryDirectory;
    self.downloadPath = [temporaryDirectory stringByAppendingPathComponent:destinationName];
}

- (void)downloaderDidReceiveExpectedContentLength:(int64_t)__unused expectedContentLength
{
    // don't need to do anything here as there's no GUI with this driver (there can be with child classes)
}

- (void)downloaderDidReceiveDataOfLength:(uint64_t)__unused length
{
    // don't need do anything here as there's no GUI with this driver (there can be with child classes)
}

- (void)downloaderDidFinishWithTemporaryDownloadData:(SPUDownloadData * _Nullable)__unused downloadData
{
    // finished. downloadData should be nil as this was a permanent download
    assert(self.updateItem);
    id<SUUpdaterPrivate> updater = self.updater;
    if ([[updater delegate] respondsToSelector:@selector(updater:didDownloadUpdate:)]) {
        [[updater delegate] updater:self.updater didDownloadUpdate:self.updateItem];
    }

    [self extractUpdate];
}

- (void)downloaderDidFailWithError:(NSError *)error
{
    NSURL *failingUrl = [error.userInfo objectForKey:NSURLErrorFailingURLErrorKey];
    if (!failingUrl) {
        failingUrl = [self.updateItem fileURL];
    }

    id<SUUpdaterPrivate> updater = self.updater;

    if ([[updater delegate] respondsToSelector:@selector(updater:failedToDownloadUpdate:error:)]) {
        [[updater delegate] updater:self.updater
             failedToDownloadUpdate:self.updateItem
                              error:error];
    }

    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:@{
                                                                                    NSLocalizedDescriptionKey: SULocalizedString(@"An error occurred while downloading the update. Please try again later.", nil),
                                                                                    NSUnderlyingErrorKey: error,
                                                                                    }];
    if (failingUrl) {
        [userInfo setObject:failingUrl forKey:NSURLErrorFailingURLErrorKey];
    }

    [self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUDownloadError userInfo:userInfo]];
}

- (void)extractUpdate
{
    id<SUUpdaterPrivate> updater = self.updater;
    id<SUUnarchiverProtocol> unarchiver = [SUUnarchiver unarchiverForPath:self.downloadPath updatingHostBundlePath:self.host.bundlePath decryptionPassword:updater.decryptionPassword];

    BOOL success = NO;
    if (!unarchiver) {
        SULog(SULogLevelError, @"Error: No valid unarchiver for %@!", self.downloadPath);
    } else {
        self.updateValidator = [[SUUpdateValidator alloc] initWithDownloadPath:self.downloadPath signatures:self.updateItem.signatures host:self.host];

        // Currently unsafe archives are the only case where we can prevalidate before extraction, but that could change in the future
        BOOL needsPrevalidation = [[unarchiver class] mustValidateBeforeExtraction];

        if (needsPrevalidation) {
            success = [self.updateValidator validateDownloadPath];
        } else {
            success = YES;
        }
    }

    if (!success) {
        NSError *reason = [NSError errorWithDomain:SUSparkleErrorDomain code:SUUnarchivingError userInfo:@{NSLocalizedDescriptionKey: @"Failed to extract update."}];
        [self unarchiverDidFailWithError:reason];
    } else {
        if ([[updater delegate] respondsToSelector:@selector(updater:willExtractUpdate:)]) {
            [[updater delegate] updater:self.updater willExtractUpdate:self.updateItem];
        }

        [unarchiver unarchiveWithCompletionBlock:^(NSError *err){
            if (err) {
                [self unarchiverDidFailWithError:err];
                return;
            }
            if ([[updater delegate] respondsToSelector:@selector(updater:didExtractUpdate:)]) {
                [[updater delegate] updater:self.updater didExtractUpdate:self.updateItem];
            }

            [self performSelectorOnMainThread:@selector(unarchiverDidFinish:) withObject:nil waitUntilDone:NO];
        } progressBlock:^(double progress) {
            [self unarchiver:nil extractedProgress:progress];
        }];
    }
}

- (void)failedToApplyDeltaUpdate
{
    // When a delta update fails to apply we fall back on updating via a full install.
    self.updateItem = self.nonDeltaUpdateItem;
    self.nonDeltaUpdateItem = nil;

    [self downloadUpdate];
}

// By default does nothing, can be overridden
- (void)unarchiver:(id)__unused ua extractedProgress:(double)__unused progress
{
}

// Note this method can be overridden (and is)
- (void)unarchiverDidFinish:(id)__unused ua
{
    assert(self.updateItem);

    [self installWithToolAndRelaunch:YES];
}

- (void)unarchiverDidFailWithError:(NSError *)err
{
    // No longer needed
    self.updateValidator = nil;

    if ([self.updateItem isDeltaUpdate]) {
        [self failedToApplyDeltaUpdate];
        return;
    }

    [self abortUpdateWithError:err];
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

- (BOOL)mayUpdateAndRestart
{
    id<SUUpdaterPrivate> updater = self.updater;
    return (!updater.delegate || ![updater.delegate respondsToSelector:@selector(updaterShouldRelaunchApplication:)] || [updater.delegate updaterShouldRelaunchApplication:self.updater]);
}

- (void)installWithToolAndRelaunch:(BOOL)relaunch displayingUserInterface:(BOOL)showUI
{
    assert(self.updateItem);
    assert(self.updateValidator);

    BOOL validationCheckSuccess = [self.updateValidator validateWithUpdateDirectory:self.tempDir];
    if (!validationCheckSuccess) {
        NSDictionary *userInfo = @{
                                   NSLocalizedDescriptionKey: SULocalizedString(@"An error occurred while extracting the archive. Please try again later.", nil),
                                   NSLocalizedFailureReasonErrorKey: SULocalizedString(@"The update is improperly signed.", nil),
                                   };
        [self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUSignatureError userInfo:userInfo]];
        return;
    }

    if (![self mayUpdateAndRestart])
    {
        [self abortUpdate];
        return;
    }

    // Give the host app an opportunity to postpone the install and relaunch.
    id<SUUpdaterPrivate> updater = self.updater;
    static BOOL postponedOnce = NO;
    id<SUUpdaterDelegate> updaterDelegate = [updater delegate];
    if (!postponedOnce) {
        if ([updaterDelegate respondsToSelector:@selector(updater:shouldPostponeRelaunchForUpdate:untilInvoking:)]) {
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[[self class] instanceMethodSignatureForSelector:@selector(installWithToolAndRelaunch:)]];
            [invocation setSelector:@selector(installWithToolAndRelaunch:)];
            [invocation setArgument:&relaunch atIndex:2];
            [invocation setTarget:self];
            postponedOnce = YES;
            if ([updaterDelegate updater:self.updater shouldPostponeRelaunchForUpdate:self.updateItem untilInvoking:invocation]) {
                return;
            }
        } else if ([updaterDelegate respondsToSelector:@selector(updater:shouldPostponeRelaunchForUpdate:)]) {
            postponedOnce = YES;
            if ([updaterDelegate updater:self.updater shouldPostponeRelaunchForUpdate:self.updateItem]) {
                return;
            }
        }
    }

    if ([updaterDelegate respondsToSelector:@selector(updater:willInstallUpdate:)]) {
        [updaterDelegate updater:self.updater willInstallUpdate:self.updateItem];
    }

    NSBundle *sparkleBundle = updater.sparkleBundle;
    if (!sparkleBundle) {
        SULog(SULogLevelError, @"Sparkle bundle is gone?");
        return;
    }

    // Copy the relauncher into a temporary directory so we can get to it after the new version's installed.
    // Only the paranoid survive: if there's already a stray copy of relaunch there, we would have problems.
    NSString *const relaunchToolSourceName = @"" SPARKLE_RELAUNCH_TOOL_NAME;
    NSString *const relaunchToolSourcePath = [sparkleBundle pathForResource:relaunchToolSourceName ofType:@"app"];
    NSString *relaunchCopyTargetPath = nil;
    NSError *error = nil;
    BOOL copiedRelaunchPath = NO;

    if (!relaunchToolSourceName || ![relaunchToolSourceName length]) {
        SULog(SULogLevelError, @"SPARKLE_RELAUNCH_TOOL_NAME not configued");
    }

    if (!relaunchToolSourcePath) {
        SULog(SULogLevelError, @"Sparkle.framework is damaged. %@ is missing", relaunchToolSourceName);
    }

    if (relaunchToolSourcePath) {
        NSString *hostBundleBaseName = [[self.host.bundlePath lastPathComponent] stringByDeletingPathExtension];
        if (!hostBundleBaseName) {
            SULog(SULogLevelError, @"Unable to get bundlePath");
            hostBundleBaseName = @"Sparkle";
        }
        NSString *relaunchCopyBaseName = [NSString stringWithFormat:@"%@ (Autoupdate).app", hostBundleBaseName];

        relaunchCopyTargetPath = [[self appCachePath] stringByAppendingPathComponent:relaunchCopyBaseName];

        SUFileManager *fileManager = [SUFileManager defaultManager];

        NSURL *relaunchToolSourceURL = [NSURL fileURLWithPath:relaunchToolSourcePath];
        NSURL *relaunchCopyTargetURL = [NSURL fileURLWithPath:relaunchCopyTargetPath];

        // We only need to run our copy of the app by spawning a task
        // Since we are copying the app to a directory that is write-accessible, we don't need to muck with owner/group IDs
        if ([self preparePathForRelaunchTool:relaunchCopyTargetPath error:&error] && [fileManager copyItemAtURL:relaunchToolSourceURL toURL:relaunchCopyTargetURL error:&error]) {
            copiedRelaunchPath = YES;

            // We probably don't need to release the quarantine, but we'll do it just in case it's necessary.
            // Perhaps in a sandboxed environment this matters more. Note that this may not be a fatal error.
            NSError *quarantineError = nil;
            if (![fileManager releaseItemFromQuarantineAtRootURL:relaunchCopyTargetURL error:&quarantineError]) {
                SULog(SULogLevelDefault, @"Warning: could not remove quarantine metadata from %@: %@. This may not be a problem, the update process will continue.", relaunchCopyTargetPath, quarantineError);
            }
        }
    }

    if (!copiedRelaunchPath) {
        [self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SURelaunchError userInfo:@{
            NSLocalizedDescriptionKey: [NSString stringWithFormat:SULocalizedString(@"An error occurred while relaunching %1$@, but the new version will be available next time you run %1$@.", nil), [self.host name]],
            NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:@"Couldn't copy relauncher (%@) to temporary path (%@)! %@",
                                                                         relaunchToolSourcePath, relaunchCopyTargetPath, (error ? [error localizedDescription] : @"")],
        }]];
        return;
    }

    self.relaunchPath = relaunchCopyTargetPath; // Set for backwards compatibility, in case any delegates modify it
    [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterWillRestartNotification object:self];
    if ([updaterDelegate respondsToSelector:@selector(updaterWillRelaunchApplication:)])
        [updaterDelegate updaterWillRelaunchApplication:self.updater];

    NSString *relaunchToolPath = [[NSBundle bundleWithPath:self.relaunchPath] executablePath];
    if (!relaunchToolPath || ![[NSFileManager defaultManager] fileExistsAtPath:self.relaunchPath]) {
        // Note that we explicitly use the host app's name here, since updating plugin for Mail relaunches Mail, not just the plugin.
        [self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SURelaunchError userInfo:@{
            NSLocalizedDescriptionKey: [NSString stringWithFormat:SULocalizedString(@"An error occurred while relaunching %1$@, but the new version will be available next time you run %1$@.", nil), [self.host name]],
            NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:@"Couldn't find the relauncher (expected to find it at %@ and %@)", relaunchToolSourcePath, self.relaunchPath],
        }]];
        return;
    }

    NSString *pathToRelaunch = [self.host bundlePath];
    if ([updaterDelegate respondsToSelector:@selector(pathToRelaunchForUpdater:)]) {
        NSString *delegateRelaunchPath = [updaterDelegate pathToRelaunchForUpdater:self.updater];
        if (delegateRelaunchPath != nil) {
            pathToRelaunch = delegateRelaunchPath;
        }
    }

    //Set relaunching flag.
    [self.host setBool:YES forUserDefaultsKey:SUUpdateRelaunchingMarkerKey];

    [NSTask launchedTaskWithLaunchPath:relaunchToolPath arguments:@[[self.host bundlePath],
                                                                    pathToRelaunch,
                                                                    [NSString stringWithFormat:@"%d", [[NSProcessInfo processInfo] processIdentifier]],
                                                                    self.tempDir,
                                                                    relaunch ? @"1" : @"0",
                                                                    showUI ? @"1" : @"0"]];
    [self terminateApp];
}

// Note: this is overridden by the automatic update driver to not terminate in some cases
- (void)terminateApp
{
    [NSApp terminate:self];
}

- (void)cleanUpDownload
{
    if (self.tempDir != nil) // tempDir contains downloadPath, so we implicitly delete both here.
    {
        BOOL success = NO;
        NSError *error = nil;
        success = [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:&error]; // Clean up the copied relauncher
        if (!success)
            [[NSWorkspace sharedWorkspace] performFileOperation:NSWorkspaceRecycleOperation source:[self.tempDir stringByDeletingLastPathComponent] destination:@"" files:@[[self.tempDir lastPathComponent]] tag:NULL];
    }
}

- (void)installerForHost:(SUHost *)aHost failedWithError:(NSError *)error
{
    if (aHost != self.host) {
        return;
    }
    NSError *dontThrow = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.relaunchPath error:&dontThrow]; // Clean up the copied relauncher
    [self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{
        NSLocalizedDescriptionKey: SULocalizedString(@"An error occurred while installing the update. Please try again later.", nil),
        NSLocalizedFailureReasonErrorKey: [error localizedDescription],
        NSUnderlyingErrorKey: error,
    }]];
}

- (void)abortUpdate
{
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
            SULog(SULogLevelError, @"Error: %@ %@ (URL %@)", errorToDisplay.localizedDescription, errorToDisplay.localizedFailureReason, [errorToDisplay.userInfo objectForKey:NSURLErrorFailingURLErrorKey]);
            errorToDisplay = [errorToDisplay.userInfo objectForKey:NSUnderlyingErrorKey];
        } while(--finiteRecursion && errorToDisplay);
    }
    if (self.download) {
        [self.download cancel];
    }

    // Notify host app that update has aborted
    id<SUUpdaterPrivate> updater = self.updater;
    id<SUUpdaterDelegate> updaterDelegate = [updater delegate];
    if ([updaterDelegate respondsToSelector:@selector(updater:didAbortWithError:)]) {
        [updaterDelegate updater:self.updater didAbortWithError:error];
    }

    [self abortUpdate];
}

@end
