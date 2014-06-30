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


@end


@implementation SUBasicUpdateDriver

- initWithUpdater:(SUUpdater *)anUpdater
{
	if ((self = [super initWithUpdater: anUpdater])) {
        downloadedData = nil;
        resumeDataFile = nil;
        downloadRetryCounter = 0;
        downloadTimer = nil;
        downloadMaxRetries = 3;
        downloadRetryInterval = 60; // 1minute default
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
	CFRetain(appcast); // We'll manage the appcast's memory ourselves so we don't have to make it an IV to support GC.
	[appcast release];

	[appcast setDelegate:self];
	[appcast setUserAgentString:[updater userAgentString]];
	[appcast fetchAppcastFromURL:URL];
}

- (id <SUVersionComparison>)versionComparator
{
	id <SUVersionComparison> comparator = nil;

	// Give the delegate a chance to provide a custom version comparator
	if ([[updater delegate] respondsToSelector:@selector(versionComparatorForUpdater:)]) {
		comparator = [[updater delegate] versionComparatorForUpdater:updater];
	}

	// If we don't get a comparator from the delegate, use the default comparator
	if (!comparator) {
		comparator = [SUStandardVersionComparator defaultComparator];
	}

	return comparator;
}

- (BOOL)isItemNewer:(SUAppcastItem *)ui
{
	return [[self versionComparator] compareVersion:[host version] toVersion:[ui versionString]] == NSOrderedAscending;
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
	NSString *skippedVersion = [host objectForUserDefaultsKey:SUSkippedVersionKey];
	if (skippedVersion == nil) { return NO; }
	return [[self versionComparator] compareVersion:[ui versionString] toVersion:skippedVersion] != NSOrderedDescending;
}

- (BOOL)itemContainsValidUpdate:(SUAppcastItem *)ui
{
	return [self hostSupportsItem:ui] && [self isItemNewer:ui] && ![self itemContainsSkippedVersion:ui];
}

- (void)appcastDidFinishLoading:(SUAppcast *)ac
{
	if ([[updater delegate] respondsToSelector:@selector(updater:didFinishLoadingAppcast:)]) {
		[[updater delegate] updater:updater didFinishLoadingAppcast:ac];
	}

	NSDictionary *userInfo = (ac != nil) ? @{SUUpdaterAppcastNotificationKey : ac} : nil;
	[[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterDidFinishLoadingAppCastNotification object:updater userInfo:userInfo];

    SUAppcastItem *item = nil;

	// Now we have to find the best valid update in the appcast.
	if ([[updater delegate] respondsToSelector:@selector(bestValidUpdateInAppcast:forUpdater:)]) // Does the delegate want to handle it?
	{
		item = [[updater delegate] bestValidUpdateInAppcast:ac forUpdater:updater];
	}
	else // If not, we'll take care of it ourselves.
	{
		// Find the first update we can actually use.
		NSEnumerator *updateEnumerator = [[ac items] objectEnumerator];
		do {
			item = [updateEnumerator nextObject];
		} while (item && ![self hostSupportsItem:item]);

		if (binaryDeltaSupported()) {
			SUAppcastItem *deltaUpdateItem = [item deltaUpdates][[host version]];
			if (deltaUpdateItem && [self hostSupportsItem:deltaUpdateItem]) {
				nonDeltaUpdateItem = [item retain];
				item = deltaUpdateItem;
			}
		}
	}

    updateItem = [item retain];
	if (ac) { CFRelease(ac); } // Remember that we're explicitly managing the memory of the appcast.
	if (updateItem == nil) { [self didNotFindUpdate]; return; }

	if ([self itemContainsValidUpdate:updateItem])
		[self didFindValidUpdate];
	else
		[self didNotFindUpdate];
}

- (void)appcast:(SUAppcast *)ac failedToLoadWithError:(NSError *)error
{
	if (ac) { CFRelease(ac); } // Remember that we're explicitly managing the memory of the appcast.
	[self abortUpdateWithError:error];
}

- (void)didFindValidUpdate
{
	if ([[updater delegate] respondsToSelector:@selector(updater:didFindValidUpdate:)])
		[[updater delegate] updater:updater didFindValidUpdate:updateItem];
	NSDictionary *userInfo = (updateItem != nil) ? @{SUUpdaterAppcastItemNotificationKey : updateItem} : nil;
	[[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterDidFindValidUpdateNotification object:updater userInfo:userInfo];
	[self downloadUpdate];
}

- (void)didNotFindUpdate
{
	if ([[updater delegate] respondsToSelector:@selector(updaterDidNotFindUpdate:)]) {
		[[updater delegate] updaterDidNotFindUpdate:updater];
	}
	[[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterDidNotFindUpdateNotification object:updater];

	[self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUNoUpdateError userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:SULocalizedString(@"You already have the newest version of %@.", nil), [host name]]}]];
}

- (void)downloadUpdate
{
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[updateItem fileURL]];
	[request setValue:[updater userAgentString] forHTTPHeaderField:@"User-Agent"];

    SULog(@"=====>Sparkle: Submitting a request for an Update");
    for (NSString* hdr in [[request allHTTPHeaderFields] allKeys])
    {
        SULog(@"%@ - %@", hdr, [[request allHTTPHeaderFields] valueForKey:hdr]);
    }

    // ----------------------------------------------------------------
    // Yahoo - setting download file size
    if ( tempDir != nil )
        [tempDir release];

    NSString* dirNamePrefix = @"Sparkle";
	//NSString *downloadFileName = [NSString stringWithFormat:@"%@ %@", [host name], [updateItem versionString]];
	NSString *downloadFileName = [NSString stringWithFormat:@"%@ %@", dirNamePrefix, [updateItem versionString]];
	tempDir = [[[host appSupportPath] stringByAppendingPathComponent:downloadFileName] retain];

    // delete old files
    NSError* error = nil;
    NSArray* appSupportContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[host appSupportPath] error:&error];
    if ( ! error && appSupportContents != nil )
    {
        for ( NSString* itemName in appSupportContents )
        {
            // if dir starts by "Sparke...." and it's different from the current dir, remove it
            if ( [itemName rangeOfString:dirNamePrefix].location != NSNotFound && [itemName compare:downloadFileName] != NSOrderedSame )
            {
                SULog(@"Removing old sparkle directory of %@", itemName);
                error = nil;
                [[NSFileManager defaultManager] removeItemAtPath:[[host appSupportPath] stringByAppendingPathComponent:itemName] error:&error];
                if ( error )
                {
                    SULog(@"Error deleting %@ - %@", itemName, [error description]);
                }
            }
        }
    }

    error = nil;
    BOOL success = [[NSFileManager defaultManager] createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:&error];
    if ( !success || error )
    {
        SULog(@"Error creating directory: %@", [error description]);
		[self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUTemporaryDirectoryError userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"Can't make a temporary directory for the update download at %@.",tempDir] forKey:NSLocalizedDescriptionKey]]];
        return;
    }
    SULog(@"Temporary download dir is %@", tempDir);

    if ( resumeDataFile != nil )
    {
        [resumeDataFile release];
        resumeDataFile = nil;
    }
	resumeDataFile = [[tempDir stringByAppendingPathComponent:@"resume.dat"] retain];
    SULog(@"Resume data file (if needed) will be %@", resumeDataFile);

    // TODO clear up old versions?
    //

    // Initialize downloaded data
    if ( downloadedData == nil )
    {
        downloadedData = [[NSMutableData dataWithCapacity: [updateItem getFileSize] ] retain];
    }

    if ( [[NSFileManager defaultManager] fileExistsAtPath: resumeDataFile] )
    {
        NSData* savedData = [[NSData dataWithContentsOfFile:resumeDataFile] retain];
        [[NSFileManager defaultManager] removeItemAtPath:resumeDataFile error:&error];
        [downloadedData appendData:savedData];
        SULog(@"Loaded %lu bytes from a previous download", [downloadedData length]);
    }

    // try resuming download
    if ( [downloadedData length] > 0 )
    {
        NSString *range = @"bytes=";
        range = [[range stringByAppendingString:[[NSNumber numberWithLongLong: [downloadedData length]] stringValue]] stringByAppendingString:@"-"];
        [request setValue:range forHTTPHeaderField:@"Range"];
    }

    urlConnection = [[NSURLConnection alloc] initWithRequest:request delegate:self];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(saveResumableData:)
                                                 name:NSApplicationWillTerminateNotification
                                               object:nil];

    SULog(@"Download started");
}

- (void) downloadUpdateTimer:(NSTimer*) timer
{
    NSLog(@"Timer to start download was fired - number of retries %lu of maximum of %lu", (unsigned long)downloadRetryCounter, (unsigned long)downloadMaxRetries);
    [downloadTimer invalidate];
    [downloadTimer release];
    downloadTimer = nil;
    if ( downloadedData != nil )
    {
        [downloadedData release];
        downloadedData = nil;
    }
    if ( urlConnection != nil )
    {
        [urlConnection release];
        urlConnection = nil;
    }
    [self downloadUpdate];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response

{
    // This method is called when the server has determined that it
    // has enough information to create the NSURLResponse object.
    SULog(@"Received response for download, content is %lu", [response expectedContentLength]);


	downloadPath = [[tempDir stringByAppendingPathComponent:[response suggestedFilename]] retain];
    SULog(@"Downloaded file name is %@", downloadPath);

    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse*) response;
    for (NSString* hdr in [[httpResponse allHeaderFields] allKeys])
    {
        SULog(@"%@ - %@", hdr, [[httpResponse allHeaderFields] valueForKey:hdr]);
    }

	if ([[updater delegate] respondsToSelector:@selector(updateStarted:estimatedSize:)])
		[[updater delegate] updateStarted:updater estimatedSize:  [updateItem getFileSize] ];

}


- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data

{
    // Append the new data to receivedData.
    [downloadedData appendData:data];

    static int counter = 0;
    if  (  ++ counter % 200 == 0 )
    {
        SULog(@"Downlading -- %ld - total=%ld",[data length], [downloadedData length]);

        if ([[updater delegate] respondsToSelector:@selector(dataReceived:currLen:)])
            [[updater delegate] dataReceived:updater currLen:  [downloadedData length]];
    }
}



- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error

{
    // Release the connection and the data object
    // by setting the properties (declared elsewhere)
    // to nil.  Note that a real-world app usually
    // requires the delegate to manage more than one
    // connection at a time, so these lines would
    // typically be replaced by code to iterate through
    // whatever data structures you are using.

    [urlConnection release];
    urlConnection = nil;

    // TODO? should we save the data for resume??
    //

    // inform the user
    SULog(@"Connection failed! Error - %@ %@",
          [error localizedDescription],
          [[error userInfo] objectForKey:NSURLErrorFailingURLStringErrorKey]);


	[self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SURelaunchError userInfo:[NSDictionary dictionaryWithObjectsAndKeys:SULocalizedString(@"An error occurred while downloading the update. Please try again later.", nil), NSLocalizedDescriptionKey, [error localizedDescription], NSLocalizedFailureReasonErrorKey, nil]]];
}



- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{

    SULog(@"Succeeded! Received %d bytes of data",[downloadedData length]);

    // Release the connection and the data object
    // by setting the properties (declared elsewhere)
    // to nil.  Note that a real-world app usually
    // requires the delegate to manage more than ne
    // connection at a time, so these lines would
    // typically be replaced by code to iterate through
    // whatever data structures you are using.

    [urlConnection release];
    urlConnection = nil;

    if ( [updateItem getFileSize] > 0 )
    {
        SULog(@"Expected file size was %ld - Actual Download size was %ld", [updateItem getFileSize], [downloadedData length]);

        if ( [updateItem getFileSize] != [downloadedData length] )
        {
            SULog(@"ERROR - downloaded file size different from what was expected");

            [self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUFileSizeError userInfo:[NSDictionary dictionaryWithObjectsAndKeys:SULocalizedString(@"An error occurred while downloading the update. Please try again later.", nil), NSLocalizedDescriptionKey, @"FILESIZE different from expected", NSLocalizedFailureReasonErrorKey, nil]]];

            return;
        }
    }
    else
        SULog(@"Downloading an update with file size specificied - no size validation performeds");


    NSError* error = nil;
    [downloadedData writeToFile:downloadPath options:nil error:&error];
    [downloadedData release];
    downloadedData = nil;
	[[NSNotificationCenter defaultCenter] removeObserver:self name:NSApplicationWillTerminateNotification object:nil];

    if ( error )
    {
        SULog(@"Error writing to disk %@", [error description]);
        [self abortUpdateWithError: error];
    }
    else
    {
        // reseting download retries after success
        downloadRetryCounter = 0;
        [self extractUpdate];
    }

}


- (BOOL)validateUpdateDownloadedToPath:(NSString *)downloadedPath extractedToPath:(NSString *)extractedPath DSASignature:(NSString *)DSASignature publicDSAKey:(NSString *)publicDSAKey
{
    NSString *newBundlePath = [SUInstaller appPathInUpdateFolder:extractedPath forHost:host];
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
	SUUnarchiver *unarchiver = [SUUnarchiver unarchiverForPath:downloadPath updatingHost:host];
	if (!unarchiver)
	{
		SULog(@"Sparkle Error: No valid unarchiver for %@!", downloadPath);
		[self unarchiverDidFail:nil];
		return;
	}
	CFRetain(unarchiver); // Manage this memory manually so we don't have to make it an IV.
	[unarchiver setDelegate:self];
	[unarchiver start];
}

- (void)failedToApplyDeltaUpdate
{
	// When a delta update fails to apply we fall back on updating via a full install.
	[updateItem release];
	updateItem = nonDeltaUpdateItem;
	nonDeltaUpdateItem = nil;

	[self downloadUpdate];
}

- (void)unarchiverDidFinish:(SUUnarchiver *)ua
{
	if (ua) { CFRelease(ua); }
	[self installWithToolAndRelaunch:YES];
}

- (void)unarchiverDidFail:(SUUnarchiver *)ua
{
	if (ua) { CFRelease(ua); }

	if ([updateItem isDeltaUpdate]) {
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
    if (![self validateUpdateDownloadedToPath:downloadPath extractedToPath:tempDir DSASignature:[updateItem DSASignature] publicDSAKey:[host publicDSAKey]])
    {
        [self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUSignatureError userInfo:@{NSLocalizedDescriptionKey: SULocalizedString(@"An error occurred while extracting the archive. Please try again later.", nil), NSLocalizedFailureReasonErrorKey: @"The update is improperly signed."}]];
        return;
	}

    if (![updater mayUpdateAndRestart])
    {
        [self abortUpdate];
        return;
    }

    NSDictionary* environ = [[NSProcessInfo processInfo] environment];
    BOOL inSandbox = (nil != [environ objectForKey:@"APP_SANDBOX_CONTAINER_ID"]);
	BOOL running10_7 = floor(NSAppKitVersionNumber) > NSAppKitVersionNumber10_6;
	BOOL useXPC = running10_7 && inSandbox &&
    [[NSFileManager defaultManager] fileExistsAtPath: [[host bundlePath] stringByAppendingPathComponent:@"Contents/XPCServices/com.yahoo.Sparkle.SandboxService.xpc"]];
    SULog(@"installWithToolAndRelaunch - using xpc=%d", useXPC);


    // Give the host app an opportunity to postpone the install and relaunch.
    static BOOL postponedOnce = NO;
    if (!postponedOnce && [[updater delegate] respondsToSelector:@selector(updater:shouldPostponeRelaunchForUpdate:untilInvoking:)])
    {
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[[self class] instanceMethodSignatureForSelector:@selector(installWithToolAndRelaunch:)]];
        [invocation setSelector:@selector(installWithToolAndRelaunch:)];
        [invocation setArgument:&relaunch atIndex:2];
        [invocation setTarget:self];
        postponedOnce = YES;
		if ([[updater delegate] updater:updater shouldPostponeRelaunchForUpdate:updateItem untilInvoking:invocation]) {
            return;
    }
	}


	if ([[updater delegate] respondsToSelector:@selector(updater:willInstallUpdate:)]) {
		[[updater delegate] updater:updater willInstallUpdate:updateItem];
	}

    NSString *const finishInstallToolName = FINISH_INSTALL_TOOL_NAME_STRING;

	// Copy the relauncher into a temporary directory so we can get to it after the new version's installed.
	// Only the paranoid survive: if there's already a stray copy of relaunch there, we would have problems.
	NSString *relaunchPathToCopy = [SPARKLE_BUNDLE pathForResource:finishInstallToolName ofType:@"app"];
	if (relaunchPathToCopy != nil)
	{
		NSString *targetPath = [[host appSupportPath] stringByAppendingPathComponent:[relaunchPathToCopy lastPathComponent]];
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
			relaunchPath = [targetPath retain];
		else
			[self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SURelaunchError userInfo:@{NSLocalizedDescriptionKey: SULocalizedString(@"An error occurred while extracting the archive. Please try again later.", nil), NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:@"Couldn't copy relauncher (%@) to temporary path (%@)! %@", relaunchPathToCopy, targetPath, (error ? [error localizedDescription] : @"")]}]];
	}

    [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterWillRestartNotification object:self];
    if ([[updater delegate] respondsToSelector:@selector(updaterWillRelaunchApplication:)])
        [[updater delegate] updaterWillRelaunchApplication:updater];

    if(!relaunchPath || ![[NSFileManager defaultManager] fileExistsAtPath:relaunchPath])
    {
        // Note that we explicitly use the host app's name here, since updating plugin for Mail relaunches Mail, not just the plugin.
        [self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SURelaunchError userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:SULocalizedString(@"An error occurred while relaunching %1$@, but the new version will be available next time you run %1$@.", nil), [host name]], NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:@"Couldn't find the relauncher (expected to find it at %@)", relaunchPath]}]];
        // We intentionally don't abandon the update here so that the host won't initiate another.
        return;
    }

    NSString *pathToRelaunch = [host bundlePath];
	if ([[updater delegate] respondsToSelector:@selector(pathToRelaunchForUpdater:)]) {
        pathToRelaunch = [[updater delegate] pathToRelaunchForUpdater:updater];
	}
    NSString *relaunchToolPath = [[relaunchPath stringByAppendingPathComponent: @"/Contents/MacOS"] stringByAppendingPathComponent: finishInstallToolName];
    NSArray *arguments = @[[host bundlePath],
                           pathToRelaunch,
                           [NSString stringWithFormat:@"%d", [[NSProcessInfo processInfo] processIdentifier]],
                           tempDir,
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
    if (tempDir != nil)	// tempDir contains downloadPath, so we implicitly delete both here.
	{
		BOOL		success = NO;
        NSError	*	error = nil;
        success = [[NSFileManager defaultManager] removeItemAtPath: tempDir error: &error]; // Clean up the copied relauncher
		if( !success )
			[[NSWorkspace sharedWorkspace] performFileOperation:NSWorkspaceRecycleOperation source:[tempDir stringByDeletingLastPathComponent] destination:@"" files:@[[tempDir lastPathComponent]] tag:NULL];
	}
}

- (void)installerForHost:(SUHost *)aHost failedWithError:(NSError *)error
{
	if (aHost != host) { return; }
	NSError	*	dontThrow = nil;
	[[NSFileManager defaultManager] removeItemAtPath: relaunchPath error: &dontThrow]; // Clean up the copied relauncher
	[self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{NSLocalizedDescriptionKey: SULocalizedString(@"An error occurred while installing the update. Please try again later.", nil), NSLocalizedFailureReasonErrorKey: [error localizedDescription]}]];
}

- (void)abortUpdate
{
    SULog(@"SUBasicUpdateDriver abort called");
	[[self retain] autorelease];	// In case the notification center was the last one holding on to us.

    if ( downloadedData != nil && [downloadedData length] > 0 )
        [self saveResumableData:nil];

    // don't remove download IF there is resume.dat file in there....
    if ( ! [[NSFileManager defaultManager] fileExistsAtPath: resumeDataFile] )
    {
        [self cleanUpDownload];
    }
    else
    {
        [self tryDownloadRetry ];
    }

    if ( downloadTimer == nil )
    {
        [[NSNotificationCenter defaultCenter] removeObserver:self];
        [super abortUpdate];
    }
}
- (void) saveResumableData:(NSNotification *)aNotification
{
    if ( aNotification != nil )
        SULog(@"saveResumableData received notification - %@", [aNotification name]);
    if ( resumeDataFile == nil ) return;

    SULog(@"application is ending/aborting download: saving resumable data to %@", resumeDataFile);
    if ( urlConnection != nil )
        [urlConnection cancel];

    if ( downloadedData != nil && [downloadedData length] > 0 )
    {
        NSError* error = nil;
        if ( resumeDataFile == nil )
            resumeDataFile = [[tempDir stringByAppendingPathComponent:@"resume.dat"] retain];
        [downloadedData writeToFile:resumeDataFile options:nil error:&error];

        if ( error )
            SULog(@"Errortrying to save resumeData: %@", [error description]);
        else
            SULog(@"Saved resume data to %@", resumeDataFile);

        [downloadedData release];
        downloadedData = nil;
    }
}

- (void) tryDownloadRetry
{
    if ( downloadRetryCounter < downloadMaxRetries )
    {
        downloadRetryCounter ++;

        SULog(@"Starting download timer - for trying to resume in %d seconds - max tries is %d", downloadRetryInterval, downloadMaxRetries);
        downloadTimer =  [[NSTimer scheduledTimerWithTimeInterval:downloadRetryInterval target:self selector:@selector(downloadUpdateTimer:) userInfo:nil repeats:NO] retain];
    }
    else
    {
        // reset retries counter BUT dont not start the timer
        // this allows for the next scheduled update to pick up full retries
        downloadRetryCounter = 0;

        if ( downloadTimer )
        {
            [downloadTimer release];
            downloadTimer = nil;
        }
        SULog(@"Current retries (%d) are more then maximum configured", downloadRetryCounter, downloadMaxRetries);
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
	if (urlConnection)
    {
        [urlConnection release];
        urlConnection = nil;

        [self tryDownloadRetry];

        if ( tempDir != nil )
        {
            [self saveResumableData: nil];
        }
    }
    else
        [self abortUpdate];
}

- (void)dealloc
{
	[updateItem release];
	[nonDeltaUpdateItem release];
	[download release];
	[downloadPath release];
	[tempDir release];
	[relaunchPath release];
	[super dealloc];
}

@end
