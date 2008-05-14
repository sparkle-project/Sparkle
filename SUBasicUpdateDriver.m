//
//  SUBasicUpdateDriver.m
//  Sparkle
//
//  Created by Andy Matuschak on 4/23/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUBasicUpdateDriver.h"
#import "Sparkle.h"

@implementation SUBasicUpdateDriver

- (void)checkForUpdatesAtURL:(NSURL *)appcastURL hostBundle:(NSBundle *)hb
{	
	hostBundle = [hb retain];
	SUAppcast *appcast = [[SUAppcast alloc] init];
	CFRetain(appcast); // We'll manage the appcast's memory ourselves so we don't have to make it an IV to support GC.
	[appcast release];
	
	[appcast setDelegate:self];
	[appcast setUserAgentString:[NSString stringWithFormat: @"%@/%@ Sparkle/1.5b1", [hostBundle name], [hostBundle displayVersion]]];
	[appcast fetchAppcastFromURL:appcastURL];
}

- (BOOL)isItemNewer:(SUAppcastItem *)ui
{
	return [[SUStandardVersionComparator defaultComparator] compareVersion:[hostBundle version]
																 toVersion:[ui versionString]] == NSOrderedAscending;
}

- (BOOL)hostSupportsItem:(SUAppcastItem *)ui
{
	if ([ui minimumSystemVersion] == nil || [[ui minimumSystemVersion] isEqualToString:@""]) { return YES; }
	return [[SUStandardVersionComparator defaultComparator] compareVersion:[ui minimumSystemVersion]
																 toVersion:[NSWorkspace systemVersionString]] != NSOrderedDescending;
}

- (BOOL)itemContainsSkippedVersion:(SUAppcastItem *)ui
{
	NSString *skippedVersion = [[SUUserDefaults standardUserDefaults] objectForKey:SUSkippedVersionKey];
	if (skippedVersion == nil) { return NO; }
	return [[SUStandardVersionComparator defaultComparator] compareVersion:[ui versionString]
																 toVersion:skippedVersion] != NSOrderedDescending;
}

- (BOOL)itemContainsValidUpdate:(SUAppcastItem *)ui
{
	return [self hostSupportsItem:ui] && [self isItemNewer:ui] && ![self itemContainsSkippedVersion:ui];
}

- (void)appcastDidFinishLoading:(SUAppcast *)ac
{
	NSArray* updates = [ac items];
	if ([updates count] > 0)
		[[SUUserDefaults standardUserDefaults] setObject:[NSDate date] forKey:SULastCheckTimeKey];
	
	// Find the first update we can actually use.
	NSEnumerator *updateEnumerator = [updates objectEnumerator];
	do {
		updateItem = [updateEnumerator nextObject];
	} while (updateItem && ![self hostSupportsItem:updateItem]);
	
	[updateItem retain];
	CFRelease(ac); // Remember that we're explicitly managing the memory of the appcast.
	if (updateItem == nil) { [self didNotFindUpdate]; return; }
	
	if ([self itemContainsValidUpdate:updateItem])
		[self didFindValidUpdate];
	else
		[self didNotFindUpdate];
}

- (void)appcast:(SUAppcast *)ac failedToLoadWithError:(NSError *)error
{
	CFRelease(ac); // Remember that we're explicitly managing the memory of the appcast.
	[self abortUpdateWithError:error];
}

- (void)didFindValidUpdate
{
	[self downloadUpdate];
}

- (void)didNotFindUpdate
{
	[self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUNoUpdateError userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:SULocalizedString(@"You already have the newest version of %@.", nil), [hostBundle name]] forKey:NSLocalizedDescriptionKey]]];
}

- (void)downloadUpdate
{
	download = [[NSURLDownload alloc] initWithRequest:[NSURLRequest requestWithURL:[updateItem fileURL]] delegate:self];	
}

- (void)download:(NSURLDownload *)d decideDestinationWithSuggestedFilename:(NSString *)name
{
	// If name ends in .txt, the server probably has a stupid MIME configuration. We'll give the developer the benefit of the doubt and chop that off.
	if ([[name pathExtension] isEqualToString:@"txt"])
		name = [name stringByDeletingPathExtension];
	
	// We create a temporary directory in /tmp and stick the file there.
	// Not using a GUID here because hdiutil for some reason chokes on GUIDs. Too long? I really have no idea.
	NSString *prefix = [NSString stringWithFormat:@"%@ %@ Update", [hostBundle name], [hostBundle version]];
	NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:prefix];
	int cnt=1;
	while ([[NSFileManager defaultManager] fileExistsAtPath:tempDir] && cnt <= 999999)
		tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@ %d", prefix, cnt++]];
	BOOL success = [[NSFileManager defaultManager] createDirectoryAtPath:tempDir attributes:nil];
	if (!success)
	{
		// Okay, something's really broken with /tmp
		[download cancel];
		[self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUTemporaryDirectoryError userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"Can't make a temporary directory for the update download at %@.",tempDir] forKey:NSLocalizedDescriptionKey]]];
	}
	
	downloadPath = [[tempDir stringByAppendingPathComponent:name] retain];
	[download setDestination:downloadPath allowOverwrite:YES];
}

- (void)downloadDidFinish:(NSURLDownload *)d
{
	[self extractUpdate];
}

- (void)download:(NSURLDownload *)download didFailWithError:(NSError *)error
{
	// Get rid of what we've downloaded so far, if anything.
	if (downloadPath != nil)
		[[NSWorkspace sharedWorkspace] performFileOperation:NSWorkspaceRecycleOperation source:[downloadPath stringByDeletingLastPathComponent] destination:@"" files:[NSArray arrayWithObject:[downloadPath lastPathComponent]] tag:NULL];
	[self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SURelaunchError userInfo:[NSDictionary dictionaryWithObjectsAndKeys:SULocalizedString(@"An error occurred while downloading the update. Please try again later.", nil), NSLocalizedDescriptionKey, [error localizedDescription], NSLocalizedFailureReasonErrorKey, nil]]];
}

- (void)extractUpdate
{
	// DSA verification, if activated by the developer
	if ([[hostBundle objectForInfoDictionaryKey:SUExpectsDSASignatureKey] boolValue])
	{
		NSString *pkeyString = [hostBundle objectForInfoDictionaryKey:SUPublicDSAKeyKey];
		if (![[NSFileManager defaultManager] validatePath:downloadPath withEncodedDSASignature:[updateItem DSASignature] withPublicDSAKey:pkeyString])
		{
			[self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUSignatureError userInfo:[NSDictionary dictionaryWithObject:@"The update is improperly signed." forKey:NSLocalizedDescriptionKey]]];
			return;
		}
	}
	
	unarchiver = [[SUUnarchiver alloc] init];
	[unarchiver setDelegate:self];
	[unarchiver unarchivePath:downloadPath];
}

- (void)unarchiverDidFinish:(SUUnarchiver *)ua
{
	[self installUpdate];
}

- (void)unarchiverDidFail:(SUUnarchiver *)ua
{
	[self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUUnarchivingError userInfo:[NSDictionary dictionaryWithObject:SULocalizedString(@"An error occurred while extracting the archive. Please try again later.", nil) forKey:NSLocalizedDescriptionKey]]];
}

- (void)installUpdate
{
	//This will copy the relauncher into NSTemporaryDirectory() just before it overwrites the bundle
	//See https://bugs.launchpad.net/sparkle/+bug/230123
	[SUInstaller installFromUpdateFolder:[downloadPath stringByDeletingLastPathComponent] overHostBundle:hostBundle delegate:self synchronously:NO relauncherPath:&relaunchPath];
}

- (void)installerFinishedForHostBundle:(NSBundle *)hb
{
	if (hb != hostBundle) { return; }
	[unarchiver cleanUp];
	[self relaunchHostApp];
}

- (void)relaunchHostApp
{
	[[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterWillRestartNotification object:self];
		
	@try
	{
		//if we failed to copy the relauncher into NSTemporaryDirectory(), use the one in the new bundle and hope for the best.
		
		NSString *realRelauncherPath = relaunchPath;
		if(!relaunchPath || ![[NSFileManager defaultManager] fileExistsAtPath:relaunchPath])
			realRelauncherPath = [[NSBundle bundleForClass:[self class]] pathForAuxiliaryExecutable:@"relaunch"];

		[NSTask launchedTaskWithLaunchPath:realRelauncherPath arguments:[NSArray arrayWithObjects:[hostBundle bundlePath], [NSString stringWithFormat:@"%d", [[NSProcessInfo processInfo] processIdentifier]], nil]];
		
		//if there's a possibility that a copy of relauncher is in NSTemporaryDirectory(), we need to be sure to clean it up
		if(relaunchPath)
		{
			[[NSWorkspace sharedWorkspace] performFileOperation:NSWorkspaceRecycleOperation 
														 source:[relaunchPath stringByDeletingLastPathComponent] 
													destination:@"" 
														  files:[NSArray arrayWithObject:[relaunchPath lastPathComponent]] 
															tag:NULL];
		}
	}
	@catch (NSException *e)
	{
		// Note that we explicitly use the host app's name here, since updating plugin for Mail relaunches Mail, not just the plugin.
		[self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SURelaunchError userInfo:[NSDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:SULocalizedString(@"An error occurred while relaunching %1$@, but the new version will be available next time you run %1$@.", nil), [[NSBundle mainBundle] name]], NSLocalizedDescriptionKey, [e reason], NSLocalizedFailureReasonErrorKey, nil]]];
		// We intentionally don't abandon the update here so that the host won't initiate another.
	}
	[NSApp terminate:self];
}

- (void)installerForHostBundle:(NSBundle *)hb failedWithError:(NSError *)error
{
	if (hb != hostBundle) { return; }
	[self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:[NSDictionary dictionaryWithObjectsAndKeys:SULocalizedString(@"An error occurred while installing the update. Please try again later.", nil), NSLocalizedDescriptionKey, [error localizedDescription], NSLocalizedFailureReasonErrorKey, nil]]];
}

- (void)abortUpdate
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[super abortUpdate];
}

- (void)abortUpdateWithError:(NSError *)error
{
	if ([error code] != SUNoUpdateError) // Let's not bother logging this.
		NSLog(@"Sparkle Error: %@", [error localizedDescription]);
	if ([error localizedFailureReason])
		NSLog(@"Sparkle Error (continued): %@", [error localizedFailureReason]);
	[self abortUpdate];
}

- (void)dealloc
{
	[hostBundle release];
	[downloadPath release];
	[unarchiver release];
	[download release];
	[super dealloc];
}

@end
