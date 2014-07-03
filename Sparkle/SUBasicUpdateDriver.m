//
//  SUBasicUpdateDriver.m
//  Sparkle
//
//  Created by Andy Matuschak on 4/23/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//
// Additions by Yahoo:
// Copyright 2014 Yahoo Inc. Licensed under the project's open source license.
//
// file size
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
#import "SUXPC.h"

#ifdef FINISH_INSTALL_TOOL_NAME
    // FINISH_INSTALL_TOOL_NAME expands to unquoted Autoupdate
    #define QUOTE_NS_STRING2(str) @"" #str
    #define QUOTE_NS_STRING1(str) QUOTE_NS_STRING2(str)
    #define FINISH_INSTALL_TOOL_NAME_STRING QUOTE_NS_STRING1(FINISH_INSTALL_TOOL_NAME)
#else
    #error FINISH_INSTALL_TOOL_NAME not defined
#endif

@interface SUBasicUpdateDriver () <NSURLConnectionDataDelegate, NSURLConnectionDelegate>

- (void) downloadUpdateTimer:(NSTimer*) timer;
- (void) saveResumableData:(NSNotification *)aNotification;
- (void) tryDownloadRetry;

@property (weak) SUAppcastItem *updateItem;
@property (strong) NSURLDownload *download;
@property (copy) NSString *downloadPath;

@property (strong) SUAppcastItem *nonDeltaUpdateItem;
@property (copy) NSString *tempDir;
@property (copy) NSString *relaunchPath;

@property (strong) NSURLConnection *urlConnection;
@property (strong) NSMutableData *downloadedData;
@property (copy) NSString *resumeDataFile;
@property (strong) NSTimer *downloadTimer;
@property (assign) NSUInteger downloadRetryCounter;
@property (assign) NSUInteger downloadRetryInterval;
@property (assign) NSUInteger downloadMaxRetries;

@end

@implementation SUBasicUpdateDriver

@synthesize updateItem;
@synthesize download;
@synthesize downloadPath;

@synthesize nonDeltaUpdateItem;
@synthesize tempDir;
@synthesize relaunchPath;

@synthesize urlConnection;
@synthesize downloadedData;
@synthesize resumeDataFile;
@synthesize downloadTimer;
@synthesize downloadRetryCounter;
@synthesize downloadRetryInterval;
@synthesize downloadMaxRetries;

- (instancetype)initWithUpdater:(SUUpdater *)anUpdater
{
	if ((self = [super initWithUpdater: anUpdater])) {
        self.downloadedData = nil;
        self.resumeDataFile = nil;
        self.downloadRetryCounter = 0;
        self.downloadTimer = nil;
        self.downloadMaxRetries = 3;
        self.downloadRetryInterval = 60; // 1minute default
    }
	return self;
}

- (void)checkForUpdatesAtURL:(NSURL *)URL host:(SUHost *)aHost
{
	[super checkForUpdatesAtURL:URL host:aHost];
	if ([aHost isRunningOnReadOnlyVolume])
	{
		[self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SURunningFromDiskImageError userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:SULocalizedString(@"%1$@ can't be updated when it's running from a read-only volume like a disk image or an optical drive. Move %1$@ to your Applications folder, relaunch it from there, and try again.", nil), [aHost name]]}]];
		return;
	}

	SUAppcast *appcast = [[SUAppcast alloc] init];

	[appcast setDelegate:self];
    [appcast setUserAgentString:[self.updater userAgentString]];
	[appcast fetchAppcastFromURL:URL];
}

- (id <SUVersionComparison>)versionComparator
{
	id <SUVersionComparison> comparator = nil;

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
	return [self hostSupportsItem:ui] && [self isItemNewer:ui] && ![self itemContainsSkippedVersion:ui];
}

- (void)appcastDidFinishLoading:(SUAppcast *)ac
{
    if ([[self.updater delegate] respondsToSelector:@selector(updater:didFinishLoadingAppcast:)]) {
        [[self.updater delegate] updater:self.updater didFinishLoadingAppcast:ac];
	}

	NSDictionary *userInfo = (ac != nil) ? @{SUUpdaterAppcastNotificationKey : ac} : nil;
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

    self.updateItem = item;
	if (self.updateItem == nil) { [self didNotFindUpdate]; return; }

	if ([self itemContainsValidUpdate:self.updateItem])
		[self didFindValidUpdate];
	else
		[self didNotFindUpdate];
}

- (void)appcast:(SUAppcast *)__unused ac failedToLoadWithError:(NSError *)error
{
	[self abortUpdateWithError:error];
}

- (void)didFindValidUpdate
{
    if ([[self.updater delegate] respondsToSelector:@selector(updater:didFindValidUpdate:)])
        [[self.updater delegate] updater:self.updater didFindValidUpdate:self.updateItem];
	NSDictionary *userInfo = (self.updateItem != nil) ? @{SUUpdaterAppcastItemNotificationKey : self.updateItem} : nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterDidFindValidUpdateNotification object:self.updater userInfo:userInfo];
	[self downloadUpdate];
}

- (void)didNotFindUpdate
{
    if ([[self.updater delegate] respondsToSelector:@selector(updaterDidNotFindUpdate:)]) {
        [[self.updater delegate] updaterDidNotFindUpdate:self.updater];
	}
    [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterDidNotFindUpdateNotification object:self.updater];

	[self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUNoUpdateError userInfo:@{
        NSLocalizedDescriptionKey: [NSString stringWithFormat:SULocalizedString(@"You already have the newest version of %@.", "'Error' message when the user checks for updates but is already current or the feed doesn't contain any updates. (not necessarily shown in UI)"), [self.host name]]
    }]];
}

- (void)downloadUpdate
{
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:self.updateItem.fileURL];
	[request setValue:self.updater.userAgentString forHTTPHeaderField:@"User-Agent"];

    SULog(@"=====>Sparkle: Submitting a request for an Update");
    for (NSString *hdr in request.allHTTPHeaderFields.allKeys)
    {
        SULog(@"%@ - %@", hdr, [request.allHTTPHeaderFields valueForKey:hdr]);
    }

    // ----------------------------------------------------------------
    // Yahoo - setting download file size

    NSString* dirNamePrefix = @"Sparkle";
	//NSString *downloadFileName = [NSString stringWithFormat:@"%@ %@", [host name], [updateItem versionString]];
	NSString *downloadFileName = [NSString stringWithFormat:@"%@ %@", dirNamePrefix, self.updateItem.versionString];
	self.tempDir = [self.host.appSupportPath stringByAppendingPathComponent:downloadFileName];

    // delete old files
    NSError* error = nil;
    NSArray* appSupportContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.host.appSupportPath error:&error];
    if (!error && appSupportContents)
    {
        for ( NSString* itemName in appSupportContents )
        {
            // if dir starts by "Sparke...." and it's different from the current dir, remove it
            if ( [itemName rangeOfString:dirNamePrefix].location != NSNotFound && [itemName compare:downloadFileName] != NSOrderedSame )
            {
                SULog(@"Removing old sparkle directory of %@", itemName);
                error = nil;
                [[NSFileManager defaultManager] removeItemAtPath:[self.host.appSupportPath stringByAppendingPathComponent:itemName] error:&error];
                if ( error )
                {
                    SULog(@"Error deleting %@ - %@", itemName, [error description]);
                }
            }
        }
    }

    error = nil;
    BOOL success = [[NSFileManager defaultManager] createDirectoryAtPath:self.tempDir withIntermediateDirectories:YES attributes:nil error:&error];
    if ( !success || error )
    {
        SULog(@"Error creating directory: %@", [error description]);
		[self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUTemporaryDirectoryError userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"Can't make a temporary directory for the update download at %@.",self.tempDir] forKey:NSLocalizedDescriptionKey]]];
        return;
    }
    SULog(@"Temporary download dir is %@", self.tempDir);

	self.resumeDataFile = [self.tempDir stringByAppendingPathComponent:@"resume.dat"];
    SULog(@"Resume data file (if needed) will be %@", self.resumeDataFile);

    // TODO clear up old versions?
    //

    // Initialize downloaded data
    if (!self.downloadedData)
    {
        self.downloadedData = [NSMutableData dataWithCapacity:self.updateItem.fileSize];
    }

    if ([[NSFileManager defaultManager] fileExistsAtPath:self.resumeDataFile])
    {
        NSData* savedData = [NSData dataWithContentsOfFile:self.resumeDataFile];
        [[NSFileManager defaultManager] removeItemAtPath:self.resumeDataFile error:&error];
        [self.downloadedData appendData:savedData];
        SULog(@"Loaded %lu bytes from a previous download", self.downloadedData.length);
    }

    // try resuming download
    if (self.downloadedData.length > 0)
    {
        NSString *range = @"bytes=";
        range = [[range stringByAppendingString:[@(self.downloadedData.length) stringValue]] stringByAppendingString:@"-"];
        [request setValue:range forHTTPHeaderField:@"Range"];
    }

    self.urlConnection = [[NSURLConnection alloc] initWithRequest:request delegate:self];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(saveResumableData:)
                                                 name:NSApplicationWillTerminateNotification
                                               object:nil];

    SULog(@"Download started");
}

- (void)downloadUpdateTimer:(NSTimer *)__unused timer
{
    NSLog(@"Timer to start download was fired - number of retries %lu of maximum of %lu", (unsigned long)self.downloadRetryCounter, (unsigned long)self.downloadMaxRetries);
    [self.downloadTimer invalidate];
    self.downloadTimer = nil;
    self.downloadedData = nil;

    self.urlConnection = nil;

    [self downloadUpdate];
}

- (void)connection:(NSURLConnection *)__unused connection didReceiveResponse:(NSURLResponse *)response

{
    // This method is called when the server has determined that it
    // has enough information to create the NSURLResponse object.
    SULog(@"Received response for download, content is %lld", response.expectedContentLength);


	self.downloadPath = [self.tempDir stringByAppendingPathComponent:[response suggestedFilename]];
    SULog(@"Downloaded file name is %@", self.downloadPath);

    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse*) response;
    for (NSString* hdr in [[httpResponse allHeaderFields] allKeys])
    {
        SULog(@"%@ - %@", hdr, [[httpResponse allHeaderFields] valueForKey:hdr]);
    }

	if ([[self.updater delegate] respondsToSelector:@selector(updateStarted:estimatedSize:)])
		[[self.updater delegate] updateStarted:self.updater estimatedSize:self.updateItem.fileSize];
}


- (void)connection:(NSURLConnection *)__unused connection didReceiveData:(NSData *)data

{
    // Append the new data to receivedData.
    [self.downloadedData appendData:data];

    static int counter = 0;
    if (++counter % 200 == 0)
    {
        SULog(@"Downlading -- %ld - total=%ld",[data length], [self.downloadedData length]);

        if ([[self.updater delegate] respondsToSelector:@selector(dataReceived:currLen:)])
            [[self.updater delegate] dataReceived:self.updater currLen:self.downloadedData.length];
    }
}



- (void)connection:(NSURLConnection *)__unused connection didFailWithError:(NSError *)error

{
    // Release the connection and the data object
    // by setting the properties (declared elsewhere)
    // to nil.  Note that a real-world app usually
    // requires the delegate to manage more than one
    // connection at a time, so these lines would
    // typically be replaced by code to iterate through
    // whatever data structures you are using.

    self.urlConnection = nil;

    // TODO? should we save the data for resume??
    //

    // inform the user
    SULog(@"Connection failed! Error - %@ %@",
          [error localizedDescription],
          [[error userInfo] objectForKey:NSURLErrorFailingURLStringErrorKey]);


	[self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SURelaunchError userInfo:[NSDictionary dictionaryWithObjectsAndKeys:SULocalizedString(@"An error occurred while downloading the update. Please try again later.", nil), NSLocalizedDescriptionKey, [error localizedDescription], NSLocalizedFailureReasonErrorKey, nil]]];
}



- (void)connectionDidFinishLoading:(NSURLConnection *)__unused connection
{

    SULog(@"Succeeded! Received %lu bytes of data", (unsigned long)self.downloadedData.length);

    // Release the connection and the data object
    // by setting the properties (declared elsewhere)
    // to nil.  Note that a real-world app usually
    // requires the delegate to manage more than ne
    // connection at a time, so these lines would
    // typically be replaced by code to iterate through
    // whatever data structures you are using.

    self.urlConnection = nil;

    if (self.updateItem.fileSize > 0)
    {
        SULog(@"Expected file size was %ld - Actual Download size was %ld", self.updateItem.fileSize, self.downloadedData.length);

        if (self.updateItem.fileSize != self.downloadedData.length)
        {
            SULog(@"ERROR - downloaded file size different from what was expected");

            [self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUFileSizeError userInfo:[NSDictionary dictionaryWithObjectsAndKeys:SULocalizedString(@"An error occurred while downloading the update. Please try again later.", nil), NSLocalizedDescriptionKey, @"FILESIZE different from expected", NSLocalizedFailureReasonErrorKey, nil]]];

            return;
        }
    }
    else
        SULog(@"Downloading an update with file size specificied - no size validation performeds");


    NSError* error = nil;
    [self.downloadedData writeToFile:self.downloadPath options:(NSDataWritingOptions)0 error:&error];
    self.downloadedData = nil;
	[[NSNotificationCenter defaultCenter] removeObserver:self name:NSApplicationWillTerminateNotification object:nil];

    if ( error )
    {
        SULog(@"Error writing to disk %@", [error description]);
        [self abortUpdateWithError: error];
    }
    else
    {
        // reseting download retries after success
        self.downloadRetryCounter = 0;
        [self extractUpdate];
    }

}


- (BOOL)validateUpdateDownloadedToPath:(NSString *)downloadedPath extractedToPath:(NSString *)extractedPath DSASignature:(NSString *)DSASignature publicDSAKey:(NSString *)publicDSAKey
{
    NSString *newBundlePath = [SUInstaller appPathInUpdateFolder:extractedPath forHost:self.host];
    if (newBundlePath)
    {
        NSError *error = nil;
        if ([SUCodeSigningVerifier codeSignatureIsValidAtPath:newBundlePath error:&error]) {
            return YES;
        } else {
            SULog(@"Code signature check on update failed: %@", error);
        }
    }

    return [SUDSAVerifier validatePath:downloadedPath withEncodedDSASignature:DSASignature withPublicDSAKey:publicDSAKey];
}



- (void)extractUpdate
{
    SUUnarchiver *unarchiver = [SUUnarchiver unarchiverForPath:self.downloadPath updatingHost:self.host];
	if (!unarchiver)
	{
		SULog(@"Sparkle Error: No valid unarchiver for %@!", self.downloadPath);
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
	[self installWithToolAndRelaunch:YES];
}

- (void)unarchiverDidFail:(SUUnarchiver *)__unused ua
{
	if ([self.updateItem isDeltaUpdate]) {
		[self failedToApplyDeltaUpdate];
		return;
	}

	[self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUUnarchivingError userInfo:@{NSLocalizedDescriptionKey: SULocalizedString(@"An error occurred while extracting the archive. Please try again later.", nil)}]];
}

- (BOOL)shouldInstallSynchronously { return NO; }

- (void)installWithToolAndRelaunch:(BOOL)relaunch
{
	// Perhaps a poor assumption but: if we're not relaunching, we assume we shouldn't be showing any UI either. Because non-relaunching installations are kicked off without any user interaction, we shouldn't be interrupting them.
	[self installWithToolAndRelaunch:relaunch displayingUserInterface:relaunch];
}

- (void)installWithToolAndRelaunch:(BOOL)relaunch displayingUserInterface:(BOOL)showUI
{
    if (![self validateUpdateDownloadedToPath:self.downloadPath extractedToPath:self.tempDir DSASignature:[self.updateItem DSASignature] publicDSAKey:[self.host publicDSAKey]])
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

    NSDictionary* environ = [[NSProcessInfo processInfo] environment];
    BOOL inSandbox = (nil != [environ objectForKey:@"APP_SANDBOX_CONTAINER_ID"]);
	BOOL running10_7 = floor(NSAppKitVersionNumber) > NSAppKitVersionNumber10_6;
	BOOL useXPC = running10_7 && inSandbox &&
    [[NSFileManager defaultManager] fileExistsAtPath: [[self.host bundlePath] stringByAppendingPathComponent:@"Contents/XPCServices/com.yahoo.Sparkle.SandboxService.xpc"]];
    SULog(@"installWithToolAndRelaunch - using xpc=%d", useXPC);


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

    NSString *const finishInstallToolName = FINISH_INSTALL_TOOL_NAME_STRING;

	// Copy the relauncher into a temporary directory so we can get to it after the new version's installed.
	// Only the paranoid survive: if there's already a stray copy of relaunch there, we would have problems.
	NSString *relaunchPathToCopy = [SPARKLE_BUNDLE pathForResource:finishInstallToolName ofType:@"app"];
	if (relaunchPathToCopy != nil)
	{
        NSString *targetPath = [[self.host appSupportPath] stringByAppendingPathComponent:[relaunchPathToCopy lastPathComponent]];
		// Only the paranoid survive: if there's already a stray copy of relaunch there, we would have problems.
		NSError *error = nil;
		[[NSFileManager defaultManager] createDirectoryAtPath: [targetPath stringByDeletingLastPathComponent] withIntermediateDirectories: YES attributes: @{} error: &error];

        BOOL copiedRelaunchTool = FALSE;
        /*
        if( useXPC )
            copiedRelaunchTool = [SUXPC copyPathWithAuthentication: relaunchPathToCopy overPath: targetPath temporaryName: nil error: &error];
        else
        */
            copiedRelaunchTool = [SUPlainInstaller copyPathWithAuthentication: relaunchPathToCopy overPath: targetPath temporaryName: nil error: &error];

		if( copiedRelaunchTool )
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
    NSString *relaunchToolPath = [[self.relaunchPath stringByAppendingPathComponent: @"/Contents/MacOS"] stringByAppendingPathComponent: finishInstallToolName];
    NSArray *arguments = @[[self.host bundlePath],
                           pathToRelaunch,
                           [NSString stringWithFormat:@"%d", [[NSProcessInfo processInfo] processIdentifier]],
                           self.tempDir,
                           relaunch ? @"1" : @"0",
                           showUI ? @"1" : @"0"];

	if( useXPC )
		[SUXPC launchTaskWithLaunchPath: relaunchToolPath arguments:arguments];
	else
        [NSTask launchedTaskWithLaunchPath: relaunchToolPath arguments: arguments];


    [NSApp terminate:self];
}

- (void)cleanUpDownload
{
    if (self.tempDir != nil)	// tempDir contains downloadPath, so we implicitly delete both here.
	{
		BOOL		success = NO;
        NSError	*	error = nil;
        success = [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error: &error]; // Clean up the copied relauncher
		if( !success )
			[[NSWorkspace sharedWorkspace] performFileOperation:NSWorkspaceRecycleOperation source:[self.tempDir stringByDeletingLastPathComponent] destination:@"" files:@[[self.tempDir lastPathComponent]] tag:NULL];
	}
}

- (void)installerForHost:(SUHost *)aHost failedWithError:(NSError *)error
{
    if (aHost != self.host) { return; }
	NSError	*	dontThrow = nil;
	[[NSFileManager defaultManager] removeItemAtPath:self.relaunchPath error: &dontThrow]; // Clean up the copied relauncher
	[self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{NSLocalizedDescriptionKey: SULocalizedString(@"An error occurred while installing the update. Please try again later.", nil), NSLocalizedFailureReasonErrorKey: [error localizedDescription]}]];
}

- (void)abortUpdate
{
    SULog(@"SUBasicUpdateDriver abort called");

    if (self.downloadedData.length > 0)
        [self saveResumableData:nil];

    // don't remove download IF there is resume.dat file in there....
    if (![[NSFileManager defaultManager] fileExistsAtPath:self.resumeDataFile])
    {
        [self cleanUpDownload];
    }
    else
    {
        [self tryDownloadRetry ];
    }

    if (!self.downloadTimer)
    {
        [[NSNotificationCenter defaultCenter] removeObserver:self];
        [super abortUpdate];
    }
}
- (void) saveResumableData:(NSNotification *)aNotification
{
    if ( aNotification != nil )
        SULog(@"saveResumableData received notification - %@", [aNotification name]);
    if (!self.resumeDataFile) return;

    SULog(@"application is ending/aborting download: saving resumable data to %@", self.resumeDataFile);
    if (self.urlConnection)
        [self.urlConnection cancel];

    if (self.downloadedData.length > 0)
    {
        NSError *error = nil;
        if (!self.resumeDataFile)
            self.resumeDataFile = [self.tempDir stringByAppendingPathComponent:@"resume.dat"];
        [self.downloadedData writeToFile:self.resumeDataFile options:(NSDataWritingOptions)0 error:&error];

        if ( error )
            SULog(@"Errortrying to save resumeData: %@", [error description]);
        else
            SULog(@"Saved resume data to %@", self.resumeDataFile);

        self.downloadedData = nil;
    }
}

- (void) tryDownloadRetry
{
    if (self.downloadRetryCounter < self.downloadMaxRetries)
    {
        self.downloadRetryCounter++;

        SULog(@"Starting download timer - for trying to resume in %lu seconds - max tries is %lu", (unsigned long)self.downloadRetryInterval, (unsigned long)self.downloadMaxRetries);
        self.downloadTimer = [NSTimer scheduledTimerWithTimeInterval:self.downloadRetryInterval target:self selector:@selector(downloadUpdateTimer:) userInfo:nil repeats:NO];
    }
    else
    {
        // reset retries counter BUT dont not start the timer
        // this allows for the next scheduled update to pick up full retries
        self.downloadRetryCounter = 0;
        self.downloadTimer = nil;
        SULog(@"Current retries (%lu) are more then maximum configured (%lu)", (unsigned long)self.downloadRetryCounter, self.downloadMaxRetries);
    }
}


- (void)abortUpdateWithError:(NSError *)error
{
	if ([error code] != SUNoUpdateError) { // Let's not bother logging this.
		SULog(@"Sparkle Error: %@", [error localizedDescription]);
	}
	if ([error localizedFailureReason]) {
		SULog(@"Sparkle Error (continued): %@", [error localizedFailureReason]);
    }

    // allow resumable downloads
	if (self.urlConnection)
    {
        self.urlConnection = nil;

        [self tryDownloadRetry];

        if (self.tempDir)
        {
            [self saveResumableData:nil];
        }
    }
    else
        [self abortUpdate];
}

@end
