//
//  SUBasicUpdateDriver.m
//  Sparkle
//
//  Created by Andy Matuschak on 4/23/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUBasicUpdateDriver.h"

#import "SUHost.h"
#import "SUDSAVerifier.h"
#import "SUInstaller.h"
#import "SUStandardVersionComparator.h"
#import "SUUnarchiver.h"
#import "SUConstants.h"
#import "SULog.h"
#import "SUPlainInstaller.h"
#import "SUPlainInstallerInternals.h"
#import "SUBinaryDeltaCommon.h"
#import "SUCodeSigningVerifier.h"
#import "SUUpdater_Private.h"

@interface SUBasicUpdateDriver ()

@property (strong) SUAppcastItem *updateItem;
@property (strong) NSURLDownload *download;
@property (copy) NSString *downloadPath;

@property (strong) SUAppcastItem *nonDeltaUpdateItem;
@property (copy) NSString *tempDir;
@property (copy) NSString *relaunchPath;

@end

@implementation SUBasicUpdateDriver

@synthesize updateItem;
@synthesize download;
@synthesize downloadPath;

@synthesize nonDeltaUpdateItem;
@synthesize tempDir;
@synthesize relaunchPath;

- (void)checkForUpdatesAtURL:(NSURL *)URL host:(SUHost *)aHost
{
    [super checkForUpdatesAtURL:URL host:aHost];
	if ([aHost isRunningOnReadOnlyVolume])
	{
        [self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SURunningFromDiskImageError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:SULocalizedString(@"%1$@ can't be updated when it's running from a read-only volume like a disk image or an optical drive. Move %1$@ to your Applications folder, relaunch it from there, and try again.", nil), [aHost name]] }]];
        return;
    }

    SUAppcast *appcast = [[SUAppcast alloc] init];

    [appcast setDelegate:self];
    [appcast setUserAgentString:[self.updater userAgentString]];
    [appcast fetchAppcastFromURL:URL];
}

- (id<SUVersionComparison>)versionComparator
{
    id<SUVersionComparison> comparator = nil;

    // Give the delegate a chance to provide a custom version comparator
    if ([[self.updater delegate] respondsToSelector:@selector(versionComparatorForUpdater:)]) {
        comparator = [[self.updater delegate] versionComparatorForUpdater:self.updater];
    }

    // If we don't get a comparator from the delegate, use the default comparator
    if (!comparator) {
        comparator = [SUStandardVersionComparator defaultComparator];
    }

    return comparator;
}

- (BOOL)isItemNewer:(SUAppcastItem *)ui
{
    return [[self versionComparator] compareVersion:[self.host version] toVersion:[ui versionString]] == NSOrderedAscending;
}

- (BOOL)hostSupportsItem:(SUAppcastItem *)ui
{
	if (([ui minimumSystemVersion] == nil || [[ui minimumSystemVersion] isEqualToString:@""]) &&
        ([ui maximumSystemVersion] == nil || [[ui maximumSystemVersion] isEqualToString:@""])) { return YES; }

    BOOL minimumVersionOK = TRUE;
    BOOL maximumVersionOK = TRUE;

    // Check minimum and maximum System Version
    if ([ui minimumSystemVersion] != nil && ![[ui minimumSystemVersion] isEqualToString:@""]) {
        minimumVersionOK = [[SUStandardVersionComparator defaultComparator] compareVersion:[ui minimumSystemVersion] toVersion:[SUHost systemVersionString]] != NSOrderedDescending;
    }
    if ([ui maximumSystemVersion] != nil && ![[ui maximumSystemVersion] isEqualToString:@""]) {
        maximumVersionOK = [[SUStandardVersionComparator defaultComparator] compareVersion:[ui maximumSystemVersion] toVersion:[SUHost systemVersionString]] != NSOrderedAscending;
    }

    return minimumVersionOK && maximumVersionOK;
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
    if ([[self.updater delegate] respondsToSelector:@selector(updater:didFinishLoadingAppcast:)]) {
        [[self.updater delegate] updater:self.updater didFinishLoadingAppcast:ac];
    }

    NSDictionary *userInfo = (ac != nil) ? @{ SUUpdaterAppcastNotificationKey: ac } : nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterDidFinishLoadingAppCastNotification object:self.updater userInfo:userInfo];

    SUAppcastItem *item = nil;

    // Now we have to find the best valid update in the appcast.
    if ([[self.updater delegate] respondsToSelector:@selector(bestValidUpdateInAppcast:forUpdater:)]) // Does the delegate want to handle it?
    {
        item = [[self.updater delegate] bestValidUpdateInAppcast:ac forUpdater:self.updater];
	}
	else // If not, we'll take care of it ourselves.
    {
        // Find the first update we can actually use.
        NSEnumerator *updateEnumerator = [[ac items] objectEnumerator];
        do {
            item = [updateEnumerator nextObject];
        } while (item && ![self hostSupportsItem:item]);

        if (binaryDeltaSupported()) {
            SUAppcastItem *deltaUpdateItem = [item deltaUpdates][[self.host version]];
            if (deltaUpdateItem && [self hostSupportsItem:deltaUpdateItem]) {
                self.nonDeltaUpdateItem = item;
                item = deltaUpdateItem;
            }
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

- (void)appcast:(SUAppcast *)__unused ac failedToLoadWithError:(NSError *)error
{
    [self abortUpdateWithError:error];
}

- (void)didFindValidUpdate
{
    assert(self.updateItem);

    if ([[self.updater delegate] respondsToSelector:@selector(updater:didFindValidUpdate:)]) {
        [[self.updater delegate] updater:self.updater didFindValidUpdate:self.updateItem];
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterDidFindValidUpdateNotification
                                                        object:self.updater
                                                      userInfo:@{ SUUpdaterAppcastItemNotificationKey: self.updateItem }];
    [self downloadUpdate];
}

- (void)didNotFindUpdate
{
    if ([[self.updater delegate] respondsToSelector:@selector(updaterDidNotFindUpdate:)]) {
        [[self.updater delegate] updaterDidNotFindUpdate:self.updater];
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
    self.download = [[NSURLDownload alloc] initWithRequest:request delegate:self];
}

- (void)download:(NSURLDownload *)__unused d decideDestinationWithSuggestedFilename:(NSString *)name
{
    NSString *downloadFileName = [NSString stringWithFormat:@"%@ %@", [self.host name], [self.updateItem versionString]];


    self.tempDir = [[self.host appSupportPath] stringByAppendingPathComponent:downloadFileName];
    int cnt = 1;
	while ([[NSFileManager defaultManager] fileExistsAtPath:self.tempDir] && cnt <= 999)
	{
        self.tempDir = [[self.host appSupportPath] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@ %d", downloadFileName, cnt++]];
    }

    // Create the temporary directory if necessary.
    BOOL success = [[NSFileManager defaultManager] createDirectoryAtPath:self.tempDir withIntermediateDirectories:YES attributes:nil error:NULL];
	if (!success)
	{
        // Okay, something's really broken with this user's file structure.
        [self.download cancel];
        [self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUTemporaryDirectoryError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Can't make a temporary directory for the update download at %@.", self.tempDir] }]];
    }

    self.downloadPath = [self.tempDir stringByAppendingPathComponent:name];
    [self.download setDestination:self.downloadPath allowOverwrite:YES];
}

- (BOOL)validateUpdateDownloadedToPath:(NSString *)downloadedPath extractedToPath:(NSString *)extractedPath DSASignature:(NSString *)DSASignature publicDSAKey:(NSString *)publicDSAKey
{
    NSString *newBundlePath = [SUInstaller appPathInUpdateFolder:extractedPath forHost:self.host];

    if (newBundlePath) {
        if ([SUCodeSigningVerifier hostApplicationIsCodeSigned]) {
            NSError *error = nil;
            if ([SUCodeSigningVerifier codeSignatureIsValidAtPath:newBundlePath error:&error]) {
                return YES;
            } else {
                SULog(@"Code signature check on update failed: %@. Sparkle will use DSA signature instead.", error);
            }
        } else {
            SULog(@"The host app is not signed using Apple Code Signing, and therefore cannot verify updates this way. Sparkle will use DSA signature instead.");
        }
    }

    if (DSASignature) {
        return [SUDSAVerifier validatePath:downloadedPath withEncodedDSASignature:DSASignature withPublicDSAKey:publicDSAKey];
    } else {
        SULog(@"The appcast item for the update has no DSA signature. The update will be rejected, because both DSA and Apple Code Signing verification failed.");
        return NO;
    }
}

- (void)downloadDidFinish:(NSURLDownload *)__unused d
{
    assert(self.updateItem);

    [self extractUpdate];
}

- (void)download:(NSURLDownload *)__unused download didFailWithError:(NSError *)error
{
	[self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SURelaunchError userInfo:@{NSLocalizedDescriptionKey: SULocalizedString(@"An error occurred while downloading the update. Please try again later.", nil), NSLocalizedFailureReasonErrorKey: [error localizedDescription]}]];
}

- (BOOL)download:(NSURLDownload *)__unused download shouldDecodeSourceDataOfMIMEType:(NSString *)encodingType
{
    // We don't want the download system to extract our gzips.
    // Note that we use a substring matching here instead of direct comparison because the docs say "application/gzip" but the system *uses* "application/x-gzip". This is a documentation bug.
    return ([encodingType rangeOfString:@"gzip"].location == NSNotFound);
}

- (void)extractUpdate
{
    SUUnarchiver *unarchiver = [SUUnarchiver unarchiverForPath:self.downloadPath updatingHost:self.host];
	if (!unarchiver)
	{
        SULog(@"Error: No valid unarchiver for %@!", self.downloadPath);
        [self unarchiverDidFail:nil];
        return;
    }
    [unarchiver setDelegate:self];
    [unarchiver start];
}

- (void)failedToApplyDeltaUpdate
{
    // When a delta update fails to apply we fall back on updating via a full install.
    self.updateItem = self.nonDeltaUpdateItem;
    self.nonDeltaUpdateItem = nil;

    [self downloadUpdate];
}

- (void)unarchiverDidFinish:(SUUnarchiver *)__unused ua
{
    assert(self.updateItem);

    [self installWithToolAndRelaunch:YES];
}

- (void)unarchiverDidFail:(SUUnarchiver *)__unused ua
{
    if ([self.updateItem isDeltaUpdate]) {
        [self failedToApplyDeltaUpdate];
        return;
    }

    [self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUUnarchivingError userInfo:@{ NSLocalizedDescriptionKey: SULocalizedString(@"An error occurred while extracting the archive. Please try again later.", nil) }]];
}

- (BOOL)shouldInstallSynchronously { return NO; }

- (void)installWithToolAndRelaunch:(BOOL)relaunch
{
    // Perhaps a poor assumption but: if we're not relaunching, we assume we shouldn't be showing any UI either. Because non-relaunching installations are kicked off without any user interaction, we shouldn't be interrupting them.
    [self installWithToolAndRelaunch:relaunch displayingUserInterface:relaunch];
}

- (void)installWithToolAndRelaunch:(BOOL)relaunch displayingUserInterface:(BOOL)showUI
{
    assert(self.updateItem);

    if (![self validateUpdateDownloadedToPath:self.downloadPath extractedToPath:self.tempDir DSASignature:self.updateItem.DSASignature publicDSAKey:self.host.publicDSAKey])
    {
        NSDictionary *userInfo = @{
            NSLocalizedDescriptionKey: SULocalizedString(@"An error occurred while extracting the archive. Please try again later.", nil),
            NSLocalizedFailureReasonErrorKey: SULocalizedString(@"The update is improperly signed.", nil),
        };
        [self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUSignatureError userInfo:userInfo]];
        return;
    }

    if (![self.updater mayUpdateAndRestart])
    {
        [self abortUpdate];
        return;
    }

    // Give the host app an opportunity to postpone the install and relaunch.
    static BOOL postponedOnce = NO;
    id<SUUpdaterDelegate> updaterDelegate = [self.updater delegate];
    if (!postponedOnce && [updaterDelegate respondsToSelector:@selector(updater:shouldPostponeRelaunchForUpdate:untilInvoking:)])
    {
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[[self class] instanceMethodSignatureForSelector:@selector(installWithToolAndRelaunch:)]];
        [invocation setSelector:@selector(installWithToolAndRelaunch:)];
        [invocation setArgument:&relaunch atIndex:2];
        [invocation setTarget:self];
        postponedOnce = YES;
        if ([updaterDelegate updater:self.updater shouldPostponeRelaunchForUpdate:self.updateItem untilInvoking:invocation]) {
            return;
        }
    }


    if ([updaterDelegate respondsToSelector:@selector(updater:willInstallUpdate:)]) {
        [updaterDelegate updater:self.updater willInstallUpdate:self.updateItem];
    }

    NSBundle *sparkleBundle = [NSBundle bundleWithIdentifier:SUBundleIdentifier];

    // Copy the relauncher into a temporary directory so we can get to it after the new version's installed.
    // Only the paranoid survive: if there's already a stray copy of relaunch there, we would have problems.
    NSString *const relaunchPathToCopy = [sparkleBundle pathForResource:[[sparkleBundle infoDictionary] objectForKey:SURelaunchToolNameKey] ofType:@"app"];
	if (relaunchPathToCopy != nil)
	{
        NSString *targetPath = [[self.host appSupportPath] stringByAppendingPathComponent:[relaunchPathToCopy lastPathComponent]];
        // Only the paranoid survive: if there's already a stray copy of relaunch there, we would have problems.
        NSError *error = nil;
        [[NSFileManager defaultManager] createDirectoryAtPath:[targetPath stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:@{} error:&error];

        if ([SUPlainInstaller copyPathWithAuthentication:relaunchPathToCopy overPath:targetPath temporaryName:nil error:&error])
            self.relaunchPath = targetPath;
        else
			[self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SURelaunchError userInfo:@{NSLocalizedDescriptionKey: SULocalizedString(@"An error occurred while extracting the archive. Please try again later.", nil), NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:@"Couldn't copy relauncher (%@) to temporary path (%@)! %@", relaunchPathToCopy, targetPath, (error ? [error localizedDescription] : @"")]}]];
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterWillRestartNotification object:self];
    if ([updaterDelegate respondsToSelector:@selector(updaterWillRelaunchApplication:)])
        [updaterDelegate updaterWillRelaunchApplication:self.updater];

    if(!self.relaunchPath || ![[NSFileManager defaultManager] fileExistsAtPath:self.relaunchPath])
    {
        // Note that we explicitly use the host app's name here, since updating plugin for Mail relaunches Mail, not just the plugin.
        [self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SURelaunchError userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:SULocalizedString(@"An error occurred while relaunching %1$@, but the new version will be available next time you run %1$@.", nil), [self.host name]], NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:@"Couldn't find the relauncher (expected to find it at %@)", self.relaunchPath]}]];
        // We intentionally don't abandon the update here so that the host won't initiate another.
        return;
    }

    NSString *pathToRelaunch = [self.host bundlePath];
    if ([updaterDelegate respondsToSelector:@selector(pathToRelaunchForUpdater:)]) {
        pathToRelaunch = [updaterDelegate pathToRelaunchForUpdater:self.updater];
    }
    NSString *relaunchToolPath = [[NSBundle bundleWithPath:self.relaunchPath] executablePath];
    [NSTask launchedTaskWithLaunchPath:relaunchToolPath arguments:@[[self.host bundlePath],
                                                                    pathToRelaunch,
                                                                    [NSString stringWithFormat:@"%d", [[NSProcessInfo processInfo] processIdentifier]],
                                                                    self.tempDir,
                                                                    relaunch ? @"1" : @"0",
                                                                    showUI ? @"1" : @"0"]];
    [self terminateApp];
}

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
    if (aHost != self.host) { return; }
    NSError *dontThrow = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.relaunchPath error:&dontThrow]; // Clean up the copied relauncher
	[self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{NSLocalizedDescriptionKey: SULocalizedString(@"An error occurred while installing the update. Please try again later.", nil), NSLocalizedFailureReasonErrorKey: [error localizedDescription]}]];
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
        SULog(@"Error: %@ %@", [error localizedDescription], [error localizedFailureReason]);
    }
    if (self.download) {
        [self.download cancel];
    }
    [self abortUpdate];
}

@end
