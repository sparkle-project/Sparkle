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
	
	if ([hostBundle isRunningFromDiskImage])
	{
		[self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SURunningFromDiskImageError userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:SULocalizedString(@"%1$@ can't be updated when it's running from a disk image. Move %1$@ to your Applications folder, relaunch it from there, and try again.", nil), [hostBundle name]] forKey:NSLocalizedDescriptionKey]]];
		return;
	}	
	
	SUAppcast *appcast = [[SUAppcast alloc] init];
	CFRetain(appcast); // We'll manage the appcast's memory ourselves so we don't have to make it an IV to support GC.
	[appcast release];
	
	[appcast setDelegate:self];
	[appcast setUserAgentString:[NSString stringWithFormat: @"%@/%@ Sparkle/1.5b4", [hostBundle name], [hostBundle displayVersion]]];
	[appcast fetchAppcastFromURL:appcastURL];
	[[SUUserDefaults standardUserDefaults] setObject:[NSDate date] forKey:SULastCheckTimeKey];
}

- (id <SUVersionComparison>)_versionComparator
{
	id <SUVersionComparison> comparator = nil;
	
	// Give the delegate a chance to provide a custom version comparator
	if ([delegate respondsToSelector:@selector(versionComparatorForHostBundle:)])
		comparator = [delegate versionComparatorForHostBundle:hostBundle];
	
	// If we don't get a comparator from the delegate, use the default comparator
	if (!comparator)
		comparator = [SUStandardVersionComparator defaultComparator];
	
	return comparator;	
}

- (BOOL)isItemNewer:(SUAppcastItem *)ui
{
	return [[self _versionComparator] compareVersion:[hostBundle version] toVersion:[ui versionString]] == NSOrderedAscending;
}

- (BOOL)hostSupportsItem:(SUAppcastItem *)ui
{
	if ([ui minimumSystemVersion] == nil || [[ui minimumSystemVersion] isEqualToString:@""]) { return YES; }
	return [[SUStandardVersionComparator defaultComparator] compareVersion:[ui minimumSystemVersion] toVersion:[NSWorkspace systemVersionString]] != NSOrderedDescending;
}

- (BOOL)itemContainsSkippedVersion:(SUAppcastItem *)ui
{
	NSString *skippedVersion = [[SUUserDefaults standardUserDefaults] objectForKey:SUSkippedVersionKey];
	if (skippedVersion == nil) { return NO; }
	return [[self _versionComparator] compareVersion:[ui versionString] toVersion:skippedVersion] != NSOrderedDescending;
}

- (BOOL)itemContainsValidUpdate:(SUAppcastItem *)ui
{
	return [self hostSupportsItem:ui] && [self isItemNewer:ui] && ![self itemContainsSkippedVersion:ui];
}

- (void)appcastDidFinishLoading:(SUAppcast *)ac
{
	if ([delegate respondsToSelector:@selector(appcastDidFinishLoading:forHostBundle:)])
		[delegate appcastDidFinishLoading:ac forHostBundle:hostBundle];
		
	// Now we have to find the best valid update in the appcast.
	if ([delegate respondsToSelector:@selector(bestValidUpdateInAppcast:forHostBundle:)]) // Does the delegate want to handle it?
	{
		updateItem = [delegate bestValidUpdateInAppcast:ac forHostBundle:hostBundle];
	}
	else // If not, we'll take care of it ourselves.
	{
		// Find the first update we can actually use.
		NSEnumerator *updateEnumerator = [[ac items] objectEnumerator];
		do {
			updateItem = [updateEnumerator nextObject];
		} while (updateItem && ![self hostSupportsItem:updateItem]);
		
		[updateItem retain];
	}
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
	if ([delegate respondsToSelector:@selector(didFindValidUpdate:toHostBundle:)])
		[delegate didFindValidUpdate:updateItem toHostBundle:hostBundle];
	[self downloadUpdate];
}

- (void)didNotFindUpdate
{
	if ([delegate respondsToSelector:@selector(didNotFindUpdateToHostBundle:)])
		[delegate didNotFindUpdateToHostBundle:hostBundle];
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

- (BOOL)download:(NSURLDownload *)download shouldDecodeSourceDataOfMIMEType:(NSString *)encodingType
{
	if ([encodingType isEqualToString:@"application/gzip"]) return NO;
	return YES;
}

- (void)extractUpdate
{
	// DSA verification, if activated by the developer
	if ([[hostBundle objectForInfoDictionaryKey:SUExpectsDSASignatureKey] boolValue])
	{
		if (![[NSFileManager defaultManager] validatePath:downloadPath withEncodedDSASignature:[updateItem DSASignature] withPublicDSAKey:[hostBundle publicDSAKey]])
		{
			[self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUSignatureError userInfo:[NSDictionary dictionaryWithObject:@"The update is improperly signed." forKey:NSLocalizedDescriptionKey]]];
			return;
		}
	}
	
	SUUnarchiver *unarchiver = [SUUnarchiver unarchiverForURL:[[[NSURL alloc] initFileURLWithPath:downloadPath] autorelease]];
	if (!unarchiver)
	{
		NSLog(@"Sparkle Error: No valid unarchiver for %@!", downloadPath);
		[self unarchiverDidFail:nil];
		return;
	}
	CFRetain(unarchiver); // Manage this memory manually so we don't have to make it an IV.
	[unarchiver setDelegate:self];
	[unarchiver start];
}

- (void)unarchiverDidFinish:(SUUnarchiver *)ua
{
	if (ua) { CFRelease(ua); }
	[self installUpdate];
}

- (void)unarchiverDidFail:(SUUnarchiver *)ua
{
	if (ua) { CFRelease(ua); }
	[self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUUnarchivingError userInfo:[NSDictionary dictionaryWithObject:SULocalizedString(@"An error occurred while extracting the archive. Please try again later.", nil) forKey:NSLocalizedDescriptionKey]]];
}

- (BOOL)shouldInstallSynchronously { return NO; }

- (void)installUpdate
{
	if ([delegate respondsToSelector:@selector(updateWillInstall:toHostBundle:)])
		[delegate updateWillInstall:updateItem toHostBundle:hostBundle];
	// Copy the relauncher into a temporary directory so we can get to it after the new version's installed.
	NSString *relaunchPathToCopy = [[NSBundle bundleForClass:[self class]]  pathForResource:@"relaunch" ofType:@""];
	NSString *targetPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[relaunchPathToCopy lastPathComponent]];
	// Only the paranoid survive: if there's already a stray copy of relaunch there, we would have problems
	[[NSFileManager defaultManager] removeFileAtPath:targetPath handler:nil];
	if ([[NSFileManager defaultManager] copyPath:relaunchPathToCopy toPath:targetPath handler:nil])
		relaunchPath = [targetPath retain];
	
	[SUInstaller installFromUpdateFolder:[downloadPath stringByDeletingLastPathComponent] overHostBundle:hostBundle delegate:self synchronously:[self shouldInstallSynchronously]];
}

- (void)installerFinishedForHostBundle:(NSBundle *)hb
{
	if (hb != hostBundle) { return; }
	[self relaunchHostApp];
}

- (void)relaunchHostApp
{
	// Give the host app an opportunity to postpone the relaunch.
	static BOOL postponedOnce = NO;
	if (!postponedOnce && [delegate respondsToSelector:@selector(shouldPostponeRelaunchForUpdate:toHostBundle:untilInvoking:)])
	{
		NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[[[self class] instanceMethodSignatureForSelector:@selector(relaunchHostApp)] retain]];
		[invocation setSelector:@selector(relaunchHostApp)];
		[invocation setTarget:self];
		postponedOnce = YES;
		if ([delegate shouldPostponeRelaunchForUpdate:updateItem toHostBundle:hostBundle untilInvoking:invocation])
			return;
	}

	[self cleanUp]; // Clean up the download and extracted files.
	
	[[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterWillRestartNotification object:self];
	if ([delegate respondsToSelector:@selector(updaterWillRelaunchApplication)])
		[delegate updaterWillRelaunchApplication];
	
	if(!relaunchPath || ![[NSFileManager defaultManager] fileExistsAtPath:relaunchPath])
	{
		// Note that we explicitly use the host app's name here, since updating plugin for Mail relaunches Mail, not just the plugin.
		[self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SURelaunchError userInfo:[NSDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:SULocalizedString(@"An error occurred while relaunching %1$@, but the new version will be available next time you run %1$@.", nil), [[NSBundle mainBundle] name]], NSLocalizedDescriptionKey, [NSString stringWithFormat:@"Couldn't find the relauncher (expected to find it at %@)", relaunchPath], NSLocalizedFailureReasonErrorKey, nil]]];
		// We intentionally don't abandon the update here so that the host won't initiate another.
		return;
	}		
	
	[NSTask launchedTaskWithLaunchPath:relaunchPath arguments:[NSArray arrayWithObjects:[hostBundle bundlePath], [NSString stringWithFormat:@"%d", [[NSProcessInfo processInfo] processIdentifier]], nil]];

	[NSApp terminate:self];
}

- (void)cleanUp
{
	[[NSFileManager defaultManager] removeFileAtPath:[downloadPath stringByDeletingLastPathComponent] handler:nil];	
}

- (void)installerForHostBundle:(NSBundle *)hb failedWithError:(NSError *)error
{
	if (hb != hostBundle) { return; }
	[[NSFileManager defaultManager] removeFileAtPath:relaunchPath handler:NULL]; // Clean up the copied relauncher.
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
	if (download)
		[download cancel];
	[self abortUpdate];
}

- (void)dealloc
{
	[hostBundle release];
	[download release];
	[downloadPath release];
	[relaunchPath release];
	[super dealloc];
}

@end
