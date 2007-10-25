//
//  SUUpdater.m
//  Sparkle
//
//  Created by Andy Matuschak on 1/4/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import "SUUpdater.h"
#import "SUAppcast.h"
#import "SUAppcastItem.h"
#import "SUUnarchiver.h"
#import "SUUtilities.h"

#import "SUUpdateAlert.h"
#import "SUAutomaticUpdateAlert.h"
#import "SUStatusController.h"

#import "NSFileManager+Authentication.h"
#import "NSFileManager+Verification.h"
#import "NSApplication+AppCopies.h"

#import <stdio.h>
#import <sys/stat.h>
#import <unistd.h>
#import <signal.h>
#import <dirent.h>

@interface SUUpdater (Private)
- (void)checkForUpdatesAndNotify:(BOOL)verbosity;
- (void)showUpdateErrorAlertWithInfo:(NSString *)info;
- (NSTimeInterval)storedCheckInterval;
- (void)abandonUpdate;
- (IBAction)installAndRestart:sender;
- (NSString *)systemVersionString;
@end

@implementation SUUpdater

- init
{
	[super init];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidFinishLaunching:) name:@"NSApplicationDidFinishLaunchingNotification" object:NSApp];	
	
	// OS version (Apple recommends using SystemVersion.plist instead of Gestalt() here, don't ask me why).
	// This code *should* use NSSearchPathForDirectoriesInDomains(NSCoreServiceDirectory, NSSystemDomainMask, YES)
	// but that returns /Library/CoreServices for some reason
	NSString *versionPlistPath = @"/System/Library/CoreServices/SystemVersion.plist";
	//gets a version string of the form X.Y.Z
	currentSystemVersion = [[[NSDictionary dictionaryWithContentsOfFile:versionPlistPath] objectForKey:@"ProductVersion"] retain];
	return self;
}

- (void)scheduleCheckWithInterval:(NSTimeInterval)interval
{
	if (checkTimer)
	{
		[checkTimer invalidate];
		checkTimer = nil;
	}
	
	checkInterval = interval;
	if (interval > 0)
		checkTimer = [NSTimer scheduledTimerWithTimeInterval:interval target:self selector:@selector(checkForUpdatesInBackground) userInfo:nil repeats:YES];
}

- (void)scheduleCheckWithIntervalObject:(NSNumber *)interval
{
	[self scheduleCheckWithInterval:[interval doubleValue]];
}

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
	// If there's a scheduled interval, we see if it's been longer than that interval since the last
	// check. If so, we perform a startup check; if not, we don't.	
	if ([self storedCheckInterval])
	{
		NSTimeInterval interval = [self storedCheckInterval];
		NSDate *lastCheck = [[NSUserDefaults standardUserDefaults] objectForKey:SULastCheckTimeKey];
		if (!lastCheck) { lastCheck = [NSDate date]; }
		NSTimeInterval intervalSinceCheck = [[NSDate date] timeIntervalSinceDate:lastCheck];
		if (intervalSinceCheck < interval)
		{
			// Hasn't been long enough; schedule a check for the future.
			[self performSelector:@selector(checkForUpdatesInBackground) withObject:nil afterDelay:(interval-intervalSinceCheck)];
			[self performSelector:@selector(scheduleCheckWithIntervalObject:) withObject:[NSNumber numberWithLong:interval] afterDelay:(interval-intervalSinceCheck)];
		}
		else
		{
			[self scheduleCheckWithInterval:interval];
			[self checkForUpdatesInBackground];
		}
	}
	else
	{
		// There's no scheduled check, so let's see if we're supposed to check on startup.
		NSNumber *shouldCheckAtStartup = [[NSUserDefaults standardUserDefaults] objectForKey:SUCheckAtStartupKey];
		if (!shouldCheckAtStartup) // hasn't been set yet; ask the user
		{
			// Let's see if there's a key in Info.plist for a default, though. We'll let that override the dialog if it's there.
			NSNumber *infoStartupValue = SUInfoValueForKey(SUCheckAtStartupKey);
			if (infoStartupValue)
			{
				shouldCheckAtStartup = infoStartupValue;
			}
			else
			{
				shouldCheckAtStartup = [NSNumber numberWithBool:NSRunAlertPanel(SULocalizedString(@"Check for updates on startup?", nil), [NSString stringWithFormat:SULocalizedString(@"Would you like %@ to check for updates on startup? If not, you can initiate the check manually from the %@ menu.", nil), SUHostAppDisplayName(), SUHostAppDisplayName()], SULocalizedString(@"Yes", nil), SULocalizedString(@"No", nil), nil) == NSAlertDefaultReturn];
			}
			[[NSUserDefaults standardUserDefaults] setObject:shouldCheckAtStartup forKey:SUCheckAtStartupKey];
		}
		
		if ([shouldCheckAtStartup boolValue])
			[self checkForUpdatesInBackground];
	}
}

- (void)dealloc
{
	[updateItem release];
    [updateAlert release];
	
	[downloadPath release];
	[statusController release];
	[downloader release];
	
	if (checkTimer)
		[checkTimer invalidate];
	
	if (currentSystemVersion)
		[currentSystemVersion release];
	
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[super dealloc];
}

- (void)checkForUpdatesInBackground
{
	[self checkForUpdatesAndNotify:NO];
}

- (IBAction)checkForUpdates:sender
{
	[self checkForUpdatesAndNotify:YES]; // if we're coming from IB, then we want to be more verbose.
}

// If the verbosity flag is YES, Sparkle will say when it can't reach the server and when there's no new update.
// This is generally useful for a menu item--when the check is explicitly invoked.
- (void)checkForUpdatesAndNotify:(BOOL)verbosity
{	
	if (updateInProgress)
	{
		if (verbosity)
		{
			NSBeep();
			if (statusController && [[statusController window] isVisible])
				[statusController showWindow:self];
			else if (updateAlert && [[updateAlert window] isVisible])
				[updateAlert showWindow:self];
			else
				[self showUpdateErrorAlertWithInfo:SULocalizedString(@"An update is already in progress!", nil)];
		}
		return;
	}
	verbose = verbosity;
	updateInProgress = YES;
	
	// A value in the user defaults overrides one in the Info.plist (so preferences panels can be created wherein users choose between beta / release feeds).
	NSString *appcastString = [[NSUserDefaults standardUserDefaults] objectForKey:SUFeedURLKey];
	if (!appcastString)
		appcastString = SUInfoValueForKey(SUFeedURLKey);
	if (!appcastString) { [NSException raise:@"SUNoFeedURL" format:@"No feed URL is specified in the Info.plist or the user defaults!"]; }
	
	SUAppcast *appcast = [[SUAppcast alloc] init];
	[appcast setDelegate:self];
	[appcast fetchAppcastFromURL:[NSURL URLWithString:appcastString]];
}

- (BOOL)automaticallyUpdates
{
	// If the SUAllowsAutomaticUpdatesKey exists and is set to NO, return NO.
	if ([SUInfoValueForKey(SUAllowsAutomaticUpdatesKey) boolValue] == NO && SUInfoValueForKey(SUAllowsAutomaticUpdatesKey)) { return NO; }
	
	// If we're not using DSA signatures, we aren't going to trust any updates automatically.
	if (![SUInfoValueForKey(SUExpectsDSASignatureKey) boolValue]) { return NO; }
	
	// If there's no setting, we default to NO.
	if (![[NSUserDefaults standardUserDefaults] objectForKey:SUAutomaticallyUpdateKey]) { return NO; }
	
	return [[[NSUserDefaults standardUserDefaults] objectForKey:SUAutomaticallyUpdateKey] boolValue];
}

- (BOOL)isAutomaticallyUpdating
{
	return [self automaticallyUpdates] && !verbose;
}

- (void)showUpdateErrorAlertWithInfo:(NSString *)info
{
	if ([self isAutomaticallyUpdating]) { return; }
	NSRunAlertPanel(SULocalizedString(@"Update Error!", nil), info, SULocalizedString(@"Cancel", nil), nil, nil);
}

- (NSTimeInterval)storedCheckInterval
{
	// Define some minimum intervals to avoid DOS-like checking attacks.
#ifdef DEBUG
	#define MIN_INTERVAL 60
#else
	#define MIN_INTERVAL 60*60
#endif
	
	// Returns the scheduled check interval stored in the user defaults / info.plist. User defaults override Info.plist.
	long interval = 0; // 0 signifies not to do timed checking.
	if ([[NSUserDefaults standardUserDefaults] objectForKey:SUScheduledCheckIntervalKey])
	{
		interval = [[[NSUserDefaults standardUserDefaults] objectForKey:SUScheduledCheckIntervalKey] longValue];
	}
	else if (SUInfoValueForKey(SUScheduledCheckIntervalKey))
	{
		interval = [SUInfoValueForKey(SUScheduledCheckIntervalKey) longValue];
	}
	if (interval >= MIN_INTERVAL)
		return interval;
	else
		return 0;
}

- (void)beginDownload
{
	if (![self isAutomaticallyUpdating])
	{
		statusController = [[SUStatusController alloc] init];
		[statusController beginActionWithTitle:SULocalizedString(@"Downloading update...", nil) maxProgressValue:0 statusText:nil];
		[statusController setButtonTitle:SULocalizedString(@"Cancel", nil) target:self action:@selector(cancelDownload:) isDefault:NO];
		[statusController showWindow:self];
	}
	
	downloader = [[NSURLDownload alloc] initWithRequest:[NSURLRequest requestWithURL:[updateItem fileURL]] delegate:self];	
}

- (void)remindMeLater
{
	// Clear out the skipped version so the dialog will actually come back if it was already skipped.
	[[NSUserDefaults standardUserDefaults] setObject:nil forKey:SUSkippedVersionKey];
	
	if (checkInterval)
		[self scheduleCheckWithInterval:checkInterval];
	else
	{
		// If the host hasn't provided a check interval, we'll use 30 minutes.
		[self scheduleCheckWithInterval:30 * 60];
	}
}

- (void)updateAlert:(SUUpdateAlert *)alert finishedWithChoice:(SUUpdateAlertChoice)choice
{
	[alert release];
	updateAlert = nil;
	switch (choice)
	{
		case SUInstallUpdateChoice:
			// Clear out the skipped version so the dialog will come back if the download fails.
			[[NSUserDefaults standardUserDefaults] setObject:nil forKey:SUSkippedVersionKey];
			[self beginDownload];
			break;
			
		case SURemindMeLaterChoice:
			updateInProgress = NO;
			[self remindMeLater];
			break;
			
		case SUSkipThisVersionChoice:
			updateInProgress = NO;
			[[NSUserDefaults standardUserDefaults] setObject:[updateItem fileVersion] forKey:SUSkippedVersionKey];
			if (checkInterval)
				[self scheduleCheckWithInterval:checkInterval];
			break;
	}			
}

- (void)showUpdatePanel
{
	updateAlert = [[SUUpdateAlert alloc] initWithAppcastItem:updateItem];
	[updateAlert setDelegate:self];
	
	// Only show the update alert if the app is active; otherwise, we'll wait until it is.
	if ([NSApp isActive])
		[updateAlert showWindow:self];
	else
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive:) name:@"NSApplicationDidBecomeActiveNotification" object:NSApp];
}

- (void)appcastDidFailToLoad:(SUAppcast *)ac
{
	[ac autorelease];
	updateInProgress = NO;
	if (verbose)
		[self showUpdateErrorAlertWithInfo:SULocalizedString(@"An error occurred in retrieving update information. Please try again later.", nil)];
}

// Override this to change the new version comparison logic!
- (BOOL)newVersionAvailable
{
	BOOL canRunOnCurrentSystem = SUStandardVersionComparison([updateItem minimumSystemVersion], [self systemVersionString]);
	return (canRunOnCurrentSystem && (SUStandardVersionComparison([updateItem fileVersion], SUHostAppVersion()) == NSOrderedAscending));
	// Want straight-up string comparison like Sparkle 1.0b3 and earlier? Uncomment the line below and comment the one above.
	// return ![SUHostAppVersion() isEqualToString:[updateItem fileVersion]];
}

- (NSString *)systemVersionString
{
	return currentSystemVersion;
}

- (void)appcastDidFinishLoading:(SUAppcast *)ac
{
	@try
	{
		if (!ac) { [NSException raise:@"SUAppcastException" format:@"Couldn't get a valid appcast from the server."]; }

		updateItem = [[ac newestItem] retain];
		[ac autorelease];

		// Record the time of the check for host app use and for interval checks on startup.
		[[NSUserDefaults standardUserDefaults] setObject:[NSDate date] forKey:SULastCheckTimeKey];

		if (![updateItem fileVersion])
		{
			[NSException raise:@"SUAppcastException" format:@"Can't extract a version string from the appcast feed. The filenames should look like YourApp_1.5.tgz, where 1.5 is the version number."];
		}

		if (!verbose && [[[NSUserDefaults standardUserDefaults] objectForKey:SUSkippedVersionKey] isEqualToString:[updateItem fileVersion]]) { updateInProgress = NO; return; }

		if ([self newVersionAvailable])
		{
			if (checkTimer)	// There's a new version! Let's disable the automated checking timer unless the user cancels.
			{
				[checkTimer invalidate];
				checkTimer = nil;
			}
			
			if ([self isAutomaticallyUpdating])
			{
				[self beginDownload];
			}
			else
			{
				[self showUpdatePanel];
			}
		}
		else
		{
			if (verbose) // We only notify on no new version when we're being verbose.
			{
				NSRunAlertPanel(SULocalizedString(@"You're up to date!", nil), [NSString stringWithFormat:SULocalizedString(@"%@ %@ is currently the newest version available.", nil), SUHostAppDisplayName(), SUHostAppVersionString()], SULocalizedString(@"OK", nil), nil, nil);
			}
			updateInProgress = NO;
		}
	}
	@catch (NSException *e)
	{
		NSLog([e reason]);
		updateInProgress = NO;
		if (verbose)
			[self showUpdateErrorAlertWithInfo:SULocalizedString(@"An error occurred in retrieving update information. Please try again later.", nil)];
	}
}

- (void)download:(NSURLDownload *)download didReceiveResponse:(NSURLResponse *)response
{
	[statusController setMaxProgressValue:[response expectedContentLength]];
}

- (void)download:(NSURLDownload *)download decideDestinationWithSuggestedFilename:(NSString *)name
{
	// If name ends in .txt, the server probably has a stupid MIME configuration. We'll give
	// the developer the benefit of the doubt and chop that off.
	if ([[name pathExtension] isEqualToString:@"txt"])
		name = [name stringByDeletingPathExtension];
	
	// We create a temporary directory in /tmp and stick the file there.
	NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
	BOOL success = [[NSFileManager defaultManager] createDirectoryAtPath:tempDir attributes:nil];
	if (!success)
	{
		[NSException raise:@"SUFailTmpWrite" format:@"Couldn't create temporary directory in /var/tmp"];
		[download cancel];
		[download release];
	}
	
	[downloadPath autorelease];
	downloadPath = [[tempDir stringByAppendingPathComponent:name] retain];
	[download setDestination:downloadPath allowOverwrite:YES];
}

- (void)download:(NSURLDownload *)download didReceiveDataOfLength:(unsigned)length
{
	[statusController setProgressValue:[statusController progressValue] + length];
	[statusController setStatusText:[NSString stringWithFormat:SULocalizedString(@"%.0lfk of %.0lfk", nil), [statusController progressValue] / 1024.0, [statusController maxProgressValue] / 1024.0]];
}

- (void)unarchiver:(SUUnarchiver *)ua extractedLength:(long)length
{
	if ([self isAutomaticallyUpdating]) { return; }
	if ([statusController maxProgressValue] == 0)
		[statusController setMaxProgressValue:[[[[NSFileManager defaultManager] fileAttributesAtPath:downloadPath traverseLink:NO] objectForKey:NSFileSize] longValue]];
	[statusController setProgressValue:[statusController progressValue] + length];
}

- (void)unarchiverDidFinish:(SUUnarchiver *)ua
{
	[ua autorelease];
	
	if ([self isAutomaticallyUpdating])
	{
		[self installAndRestart:self];
	}
	else
	{
		[statusController beginActionWithTitle:SULocalizedString(@"Ready to install!", nil) maxProgressValue:1 statusText:nil];
		[statusController setProgressValue:1]; // fill the bar
		[statusController setButtonTitle:SULocalizedString(@"Install and Relaunch", nil) target:self action:@selector(installAndRestart:) isDefault:YES];
		[NSApp requestUserAttention:NSInformationalRequest];
	}
}

- (void)unarchiverDidFail:(SUUnarchiver *)ua
{
	[ua autorelease];
	[self showUpdateErrorAlertWithInfo:SULocalizedString(@"An error occurred while extracting the archive. Please try again later.", nil)];
	[self abandonUpdate];
}

- (void)extractUpdate
{
	// Now we have to extract the downloaded archive.
	if (![self isAutomaticallyUpdating])
		[statusController beginActionWithTitle:SULocalizedString(@"Extracting update...", nil) maxProgressValue:0 statusText:nil];
	
	@try 
	{
		// If the developer's provided a sparkle:md5Hash attribute on the enclosure, let's verify that.
		if ([updateItem MD5Sum] && ![[NSFileManager defaultManager] validatePath:downloadPath withMD5Hash:[updateItem MD5Sum]])
		{
			[NSException raise:@"SUUnarchiveException" format:@"MD5 verification of the update archive failed."];
		}
		
		// DSA verification, if activated by the developer
		if ([SUInfoValueForKey(SUExpectsDSASignatureKey) boolValue])
		{
			NSString *dsaSignature = [updateItem DSASignature];
			if (![[NSFileManager defaultManager] validatePath:downloadPath withEncodedDSASignature:dsaSignature])
			{
				[NSException raise:@"SUUnarchiveException" format:@"DSA verification of the update archive failed."];
			}
		}
		
		SUUnarchiver *unarchiver = [[SUUnarchiver alloc] init];
		[unarchiver setDelegate:self];
		[unarchiver unarchivePath:downloadPath]; // asynchronous extraction!
	}
	@catch(NSException *e) {
		NSLog([e reason]);
		[self showUpdateErrorAlertWithInfo:SULocalizedString(@"An error occurred while extracting the archive. Please try again later.", nil)];
		[self abandonUpdate];
	}	
}

- (void)downloadDidFinish:(NSURLDownload *)download
{
	[download release];
	downloader = nil;
	[self extractUpdate];
}

- (void)abandonUpdate
{
	[updateItem autorelease];
	updateItem = nil;
	[statusController close];
	[statusController autorelease];
	statusController = nil;
	updateInProgress = NO;
}

- (void)download:(NSURLDownload *)download didFailWithError:(NSError *)error
{
	[self abandonUpdate];
	
	NSLog(@"Download error: %@", [error localizedDescription]);
	[self showUpdateErrorAlertWithInfo:SULocalizedString(@"An error occurred while trying to download the file. Please try again later.", nil)];
}

- (IBAction)installAndRestart:sender
{
	NSString *currentAppPath = [[NSBundle mainBundle] bundlePath];
	NSString *newAppDownloadPath = [[downloadPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:[SUUnlocalizedInfoValueForKey(@"CFBundleName") stringByAppendingPathExtension:@"app"]];
	@try 
	{
		if (![self isAutomaticallyUpdating])
		{
			[statusController beginActionWithTitle:SULocalizedString(@"Installing update...", nil) maxProgressValue:0 statusText:nil];
			[statusController setButtonEnabled:NO];
			
			// We have to wait for the UI to update.
			NSEvent *event;
			while((event = [NSApp nextEventMatchingMask:NSAnyEventMask untilDate:nil inMode:NSDefaultRunLoopMode dequeue:YES]))
				[NSApp sendEvent:event];			
		}
		
		// We assume that the archive will contain a file named {CFBundleName}.app
		// (where, obviously, CFBundleName comes from Info.plist)
		if (!SUUnlocalizedInfoValueForKey(@"CFBundleName")) { [NSException raise:@"SUInstallException" format:@"This application has no CFBundleName! This key must be set to the application's name."]; }

		// Search subdirectories for the application
		NSString *file, *appName = [SUUnlocalizedInfoValueForKey(@"CFBundleName") stringByAppendingPathExtension:@"app"];
		NSDirectoryEnumerator *dirEnum = [[NSFileManager defaultManager] enumeratorAtPath:[downloadPath stringByDeletingLastPathComponent]];
		while ((file = [dirEnum nextObject]))
		{
			// Some DMGs have symlinks into /Applications! That's no good!
			if ([file isEqualToString:@"/Applications"])
				[dirEnum skipDescendents];
			if ([[file lastPathComponent] isEqualToString:appName]) // We found one!
			{
				newAppDownloadPath = [[downloadPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:file];
				break;
			}
			if ([[file pathExtension] isEqualToString:@".app"]) // No point in looking in app bundles.
				[dirEnum skipDescendents];
		}
		
		if (!newAppDownloadPath || ![[NSFileManager defaultManager] fileExistsAtPath:newAppDownloadPath])
		{
			[NSException raise:@"SUInstallException" format:@"The update archive didn't contain an application with the proper name: %@. Remember, the updated app's file name must be identical to {CFBundleName}.app", [SUInfoValueForKey(@"CFBundleName") stringByAppendingPathExtension:@"app"]];
		}
	}
	@catch(NSException *e) 
	{
		NSLog([e reason]);
		[self showUpdateErrorAlertWithInfo:SULocalizedString(@"An error occurred during installation. Please try again later.", nil)];
		[self abandonUpdate];
		return;
	}
	
	if ([self isAutomaticallyUpdating]) // Don't do authentication if we're automatically updating; that'd be surprising.
	{
		int tag = 0;
		BOOL result = [[NSWorkspace sharedWorkspace] performFileOperation:NSWorkspaceRecycleOperation source:[currentAppPath stringByDeletingLastPathComponent] destination:@"" files:[NSArray arrayWithObject:[currentAppPath lastPathComponent]] tag:&tag];
		result &= [[NSFileManager defaultManager] movePath:newAppDownloadPath toPath:currentAppPath handler:nil];
		if (!result)
		{
			[self abandonUpdate];
			return;
		}
	}
	else // But if we're updating by the action of the user, do an authenticated move.
	{
		// Outside of the @try block because we want to be a little more informative on this error.
		if (![[NSFileManager defaultManager] movePathWithAuthentication:newAppDownloadPath toPath:currentAppPath])
		{
			[self showUpdateErrorAlertWithInfo:[NSString stringWithFormat:SULocalizedString(@"%@ does not have permission to write to the application's directory! Are you running off a disk image? If not, ask your system administrator for help.", nil), SUHostAppDisplayName()]];
			[self abandonUpdate];
			return;
		}
	}
		
	// Prompt for permission to restart if we're automatically updating.
	if ([self isAutomaticallyUpdating])
	{
		SUAutomaticUpdateAlert *alert = [[SUAutomaticUpdateAlert alloc] initWithAppcastItem:updateItem];
		if ([NSApp runModalForWindow:[alert window]] == NSAlertAlternateReturn)
		{
			[alert release];
			return;
		}
	}
	
	[[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterWillRestartNotification object:self];

	// Thanks to Allan Odgaard for this restart code, which is much more clever than mine was.
	setenv("LAUNCH_PATH", [currentAppPath UTF8String], 1);
	setenv("TEMP_FOLDER", [[downloadPath stringByDeletingLastPathComponent] UTF8String], 1); // delete the temp stuff after it's all over
	system("/bin/bash -c '{ for (( i = 0; i < 3000 && $(echo $(/bin/ps -xp $PPID|/usr/bin/wc -l))-1; i++ )); do\n"
		   "    /bin/sleep .2;\n"
		   "  done\n"
		   "  if [[ $(/bin/ps -xp $PPID|/usr/bin/wc -l) -ne 2 ]]; then\n"
		   "    /usr/bin/open \"${LAUNCH_PATH}\"\n"
		   "  fi\n"
		   "  rm -rf \"${TEMP_FOLDER}\"\n"
		   "} &>/dev/null &'");
	[NSApp terminate:self];	
}

- (IBAction)cancelDownload:sender
{
	if (downloader)
	{
		[downloader cancel];
		[downloader release];
	}
	[self abandonUpdate];
	
	if (checkInterval)
	{
		[self scheduleCheckWithInterval:checkInterval];
	}
}

- (void)applicationDidBecomeActive:(NSNotification *)aNotification
{
	// We don't want to display the update alert until the application becomes active.
	[updateAlert showWindow:self];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:@"NSApplicationDidBecomeActiveNotification" object:NSApp];
}

@end
