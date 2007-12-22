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
#import "NSBundle+SUAdditions.h"
#import "SUUserDefaults.h"
#import "SUVersionComparisonProtocol.h"
#import "SUStandardVersionComparator.h"

#import "SUUpdateAlert.h"
#import "SUAutomaticUpdateAlert.h"
#import "SUStatusController.h"

#import "NSFileManager+Authentication.h"
#import "NSFileManager+Verification.h"

#import <stdio.h>
#import <sys/stat.h>
#import <unistd.h>
#import <signal.h>
#import <dirent.h>

@interface SUUpdater (Private)
- (void)beginUpdateCheck;
- (void)showUpdateAlert;
- (void)beginDownload;
- (void)extractUpdate;
- (void)showUpdateErrorAlertWithInfo:(NSString *)info;
- (NSTimeInterval)storedCheckInterval;
- (void)abandonUpdate;
- (IBAction)installAndRestart:sender;
- (NSString *)systemVersionString;
@end

@implementation SUUpdater

#pragma mark Initialization

// SUUpdater's a singleton now! And I'm enforcing it!
+ (id)allocWithZone:(NSZone *)zone
{
	static SUUpdater *sharedUpdater = nil;
	if (sharedUpdater == nil)
		sharedUpdater = [super allocWithZone:zone];
    return sharedUpdater;
}

+ (SUUpdater *)sharedUpdater
{
	return [SUUpdater alloc];
}

- init
{
	self = [super init];
	[self setHostBundle:[NSBundle mainBundle]];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidFinishLaunching:) name:NSApplicationDidFinishLaunchingNotification object:NSApp];
	return self;
}

- (void)setHostBundle:(NSBundle *)hb
{
	[hostBundle release];
	hostBundle = [hb retain];
	[[SUUserDefaults standardUserDefaults] setIdentifier:[hostBundle bundleIdentifier]];
}

#pragma mark Automatic check support

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
	// If the user has been asked about automatic checks and said no, get out of here.
	if ([[SUUserDefaults standardUserDefaults] objectForKey:SUEnableAutomaticChecksKey] &&
		[[SUUserDefaults standardUserDefaults] boolForKey:SUEnableAutomaticChecksKey] == NO) { return; }
	
	// Has he been asked already?
	if ([[SUUserDefaults standardUserDefaults] objectForKey:SUEnableAutomaticChecksKey] == nil)
	{
		// Now, we don't want to ask the user for permission to do a weird thing on the first launch.
		// We wait until the second launch.
		if ([[SUUserDefaults standardUserDefaults] boolForKey:SUHasLaunchedBeforeKey] == NO)
		{
			[[SUUserDefaults standardUserDefaults] setBool:YES forKey:SUHasLaunchedBeforeKey];
			return;
		}
		
		// The user's never been asked, so let's see if they want automatic checking.
		NSAlert *alert = [NSAlert alertWithMessageText:SULocalizedString(@"Allow automatic update checking?", nil) defaultButton:SULocalizedString(@"Allow", nil) alternateButton:SULocalizedString(@"Don't Allow", nil) otherButton:nil informativeTextWithFormat:SULocalizedString(@"Would you like %1$@ to automatically check for updates to itself? If not, you can check for updates manually from the %1$@ menu.", nil), [hostBundle name]];
		[alert setIcon:[hostBundle icon]];
		[[SUUserDefaults standardUserDefaults] setBool:([alert runModal] == NSAlertDefaultReturn) forKey:SUEnableAutomaticChecksKey];
		
		// Let's get rid of that extra key cluttering up the user defaults, too.
		[[SUUserDefaults standardUserDefaults] setObject:nil forKey:SUHasLaunchedBeforeKey];
	}
	
	if ([[SUUserDefaults standardUserDefaults] boolForKey:SUEnableAutomaticChecksKey] == YES)
	{
		// Find the stored check interval. User defaults override Info.plist.
		if ([[SUUserDefaults standardUserDefaults] objectForKey:SUScheduledCheckIntervalKey])
			checkInterval = [[[SUUserDefaults standardUserDefaults] objectForKey:SUScheduledCheckIntervalKey] longValue];
		else if ([hostBundle objectForInfoDictionaryKey:SUScheduledCheckIntervalKey])
			checkInterval = [[hostBundle objectForInfoDictionaryKey:SUScheduledCheckIntervalKey] longValue];
		
		if (checkInterval < SU_MIN_CHECK_INTERVAL) // This can also mean one that isn't set.
			checkInterval = SU_DEFAULT_CHECK_INTERVAL;
		
		// How long has it been since last we checked for an update?
		NSDate *lastCheckDate = [[SUUserDefaults standardUserDefaults] objectForKey:SULastCheckTimeKey];
		if (!lastCheckDate) { lastCheckDate = [NSDate distantPast]; }
		NSTimeInterval intervalSinceCheck = [[NSDate date] timeIntervalSinceDate:lastCheckDate];
		
		// Now we want to figure out how long until we check again.
		NSTimeInterval delayUntilCheck;
		if (intervalSinceCheck < [self storedCheckInterval])
			delayUntilCheck = ([self storedCheckInterval] - intervalSinceCheck); // It hasn't been long enough.
		else
			delayUntilCheck = 0; // We're overdue! Run one now.
		
		[self performSelector:@selector(checkForUpdatesInBackground) withObject:nil afterDelay:delayUntilCheck];
		[self performSelector:@selector(scheduleCheckWithIntervalObject:) withObject:[NSNumber numberWithDouble:[self storedCheckInterval]] afterDelay:delayUntilCheck];
	}
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

// An unfortunate necessity in order to use performSelector:withObject:afterDelay:
- (void)scheduleCheckWithIntervalObject:(NSNumber *)interval
{
	[self scheduleCheckWithInterval:[interval doubleValue]];
}

- (void)checkForUpdatesInBackground
{
	userInitiated = NO;
	[self beginUpdateCheck];
}

- (IBAction)checkForUpdates:sender
{
	userInitiated = YES;
	[self beginUpdateCheck];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
	if ([item action] == @selector(checkForUpdates:))
	{
		if (updateInProgress)
			return NO;
		else
			return YES;
	}
	return YES;
}

- (BOOL)automaticallyUpdates
{
	// If the SUAllowsAutomaticUpdatesKey exists and is set to NO, return NO.
	if ([[hostBundle objectForInfoDictionaryKey:SUAllowsAutomaticUpdatesKey] boolValue] == NO)
		return NO;
	
	// If we're not using DSA signatures, we aren't going to trust any updates automatically.
	if ([[hostBundle objectForInfoDictionaryKey:SUExpectsDSASignatureKey] boolValue] != YES)
		return NO;
	
	// If there's no setting, or it's set to no, we're not automatically updating.
	if ([[SUUserDefaults standardUserDefaults] boolForKey:SUAutomaticallyUpdateKey] != YES)
		return NO;
	
	return YES; // Otherwise, we're good to go.
}

- (BOOL)isAutomaticallyUpdating
{
	return [self automaticallyUpdates] && !userInitiated;
}

#pragma mark Appcast-fetching phase

- (void)beginUpdateCheck
{		
	if ([hostBundle isRunningFromDiskImage])
	{
		if (userInitiated)
			[self showUpdateErrorAlertWithInfo:[NSString stringWithFormat:SULocalizedString(@"%1$@ can't be updated when it's running from a disk image. Move %1$@ to your Applications folder, relaunch it, and try again.", nil), [hostBundle name]]];
		return;
	}
	
	if (updateInProgress) { return; }
	updateInProgress = YES;
	
	// A value in the user defaults overrides one in the Info.plist (so preferences panels can be created wherein users choose between beta / release feeds).
	NSString *appcastString = [[SUUserDefaults standardUserDefaults] objectForKey:SUFeedURLKey];
	if (!appcastString)
		appcastString = [hostBundle objectForInfoDictionaryKey:SUFeedURLKey];
	if (!appcastString)
		[NSException raise:@"SUNoFeedURL" format:@"You must specify the URL of the appcast as the SUFeedURLKey in either the Info.plist or the user defaults!"];
	
	SUAppcast *appcast = [[SUAppcast alloc] init];
	[appcast setDelegate:self];
	[appcast fetchAppcastFromURL:[NSURL URLWithString:appcastString]];
}

- (BOOL)newVersionAvailable
{
	// First, we have to make sure that the newest version can run on the user's system.
	// Apple recommends using SystemVersion.plist instead of Gestalt() here, don't ask me why.
	// This code *should* use NSSearchPathForDirectoriesInDomains(NSCoreServiceDirectory, NSSystemDomainMask, YES)
	// but that returns /Library/CoreServices for some reason
	NSString *versionPlistPath = @"/System/Library/CoreServices/SystemVersion.plist";
	// This returns a version string of the form X.Y.Z
	NSString *systemVersionString = [[NSDictionary dictionaryWithContentsOfFile:versionPlistPath] objectForKey:@"ProductVersion"];
	id <SUVersionComparison> comparator = [SUStandardVersionComparator defaultComparator];
	BOOL canRunOnCurrentSystem = ([comparator compareVersion:[updateItem minimumSystemVersion] toVersion:systemVersionString] != NSOrderedDescending);
	return (canRunOnCurrentSystem && ([comparator compareVersion:[hostBundle version] toVersion:[updateItem fileVersion]]) == NSOrderedAscending);
}

- (void)appcastDidFinishLoading:(SUAppcast *)ac
{
	@try
	{
		if (!ac)
			[NSException raise:@"SUAppcastException" format:@"Couldn't get a valid appcast from the server."];
		
		updateItem = [[ac newestItem] retain];
		[ac autorelease];
		
		// Record the time of the check for host app use and for interval checks on startup.
		[[SUUserDefaults standardUserDefaults] setObject:[NSDate date] forKey:SULastCheckTimeKey];
		
		if (![updateItem fileVersion])
		{
			[NSException raise:@"SUAppcastException" format:@"Can't extract a version string from the appcast feed. The filenames should look like YourApp_1.5.tgz, where 1.5 is the version number."];
		}
		
		if (!userInitiated && [[[SUUserDefaults standardUserDefaults] objectForKey:SUSkippedVersionKey] isEqualToString:[updateItem fileVersion]]) { [self abandonUpdate]; return; }
		
		if ([self newVersionAvailable])
		{
			if (checkTimer)	// There's a new version! Let's disable the automated checking timer.
			{
				[checkTimer invalidate];
				checkTimer = nil;
			}
			
			if ([self isAutomaticallyUpdating])
				[self beginDownload];
			else
				[self showUpdateAlert];
		}
		else
		{
			if (userInitiated)
			{
				NSAlert *alert = [NSAlert alertWithMessageText:SULocalizedString(@"You're up to date!", nil) defaultButton:SULocalizedString(@"OK", nil) alternateButton:nil otherButton:nil informativeTextWithFormat:SULocalizedString(@"%@ %@ is currently the newest version available.", nil), [hostBundle name], [hostBundle displayVersion]];
				[alert setIcon:[hostBundle icon]];
				[alert runModal];
			}
			[self abandonUpdate];
		}
	}
	@catch (NSException *e)
	{
		[self abandonUpdate];
		if (userInitiated)
		{
			NSLog([e reason]);
			[self showUpdateErrorAlertWithInfo:SULocalizedString(@"An error occurred in retrieving update information. Please try again later.", nil)];
		}
	}
}

- (NSString *)userAgentForAppcast:(SUAppcast *)ac
{
	return [NSString stringWithFormat: @"%@/%@ Sparkle/1.5b1", [hostBundle name], [hostBundle displayVersion]];
}

- (void)appcastDidFailToLoad:(SUAppcast *)ac
{
	[ac autorelease];
	updateInProgress = NO;
	if (userInitiated)
		[self showUpdateErrorAlertWithInfo:SULocalizedString(@"An error occurred in retrieving update information. Please try again later.", nil)];
}

#pragma mark The update alert phase

- (void)showUpdateAlert
{
	updateAlert = [[SUUpdateAlert alloc] initWithAppcastItem:updateItem hostBundle:hostBundle];
	[updateAlert setDelegate:self];
	
	// Only show the update alert if the app is active; otherwise, we'll wait until it is.
	if ([NSApp isActive])
		[updateAlert showWindow:self];
	else
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive:) name:@"NSApplicationDidBecomeActiveNotification" object:NSApp];
}

- (void)applicationDidBecomeActive:(NSNotification *)aNotification
{
	// We don't want to display the update alert until the application becomes active.
	[updateAlert showWindow:self];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:@"NSApplicationDidBecomeActiveNotification" object:NSApp];
}

- (void)updateAlert:(SUUpdateAlert *)alert finishedWithChoice:(SUUpdateAlertChoice)choice
{
	[alert release];
	updateAlert = nil;
	switch (choice)
	{
		case SUInstallUpdateChoice:
			// Clear out the skipped version so the dialog will come back if the download fails.
			[[SUUserDefaults standardUserDefaults] setObject:nil forKey:SUSkippedVersionKey];
			[self beginDownload];
			break;
			
		case SURemindMeLaterChoice:
			// Clear out the skipped version so the dialog will actually come back if it was already skipped.
			[[SUUserDefaults standardUserDefaults] setObject:nil forKey:SUSkippedVersionKey];	
			[self abandonUpdate];
			break;
			
		case SUSkipThisVersionChoice:
			[[SUUserDefaults standardUserDefaults] setObject:[updateItem fileVersion] forKey:SUSkippedVersionKey];
			[self abandonUpdate];
			break;
	}			
}

#pragma mark The downloading phase

- (void)beginDownload
{
	if (![self isAutomaticallyUpdating])
	{
		statusController = [[SUStatusController alloc] initWithHostBundle:hostBundle];
		[statusController beginActionWithTitle:SULocalizedString(@"Downloading update...", nil) maxProgressValue:0 statusText:nil];
		[statusController setButtonTitle:SULocalizedString(@"Cancel", nil) target:self action:@selector(cancelDownload:) isDefault:NO];
		[statusController showWindow:self];
	}
	
	downloader = [[NSURLDownload alloc] initWithRequest:[NSURLRequest requestWithURL:[updateItem fileURL]] delegate:self];	
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
	// Not using a GUID here because hdiutil for some reason chokes on GUIDs. Too long? I really have no idea.
	NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"update"];
	int cnt=1;
	while ([[NSFileManager defaultManager] fileExistsAtPath:tempDir] && cnt <= 999)
		tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"update%d", cnt++]];
	BOOL success = [[NSFileManager defaultManager] createDirectoryAtPath:tempDir attributes:nil];
	if (!success)
	{
		[NSException raise:@"SUFailTmpWrite" format:@"Couldn't create temporary directory at %@", tempDir];
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

- (IBAction)cancelDownload:sender
{
	if (downloader)
	{
		[downloader cancel];
		[downloader release];
	}
	[self abandonUpdate];
}

- (void)downloadDidFinish:(NSURLDownload *)download
{
	[download release];
	downloader = nil;
	[self extractUpdate];
}

- (void)download:(NSURLDownload *)download didFailWithError:(NSError *)error
{
	[self abandonUpdate];
	
	NSLog(@"Download error: %@", [error localizedDescription]);
	[self showUpdateErrorAlertWithInfo:SULocalizedString(@"An error occurred while trying to download the file. Please try again later.", nil)];
}

#pragma mark Extraction phase

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
		[statusController beginActionWithTitle:SULocalizedString(@"Ready to Install", nil) maxProgressValue:1 statusText:nil];
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
		// DSA verification, if activated by the developer
		if ([[hostBundle objectForInfoDictionaryKey:SUExpectsDSASignatureKey] boolValue])
		{
			NSString *dsaSignature = [updateItem DSASignature];
			NSString *pkeyString = [hostBundle objectForInfoDictionaryKey:SUPublicDSAKeyKey]; // Fetch the app's public DSA key.
			if (![[NSFileManager defaultManager] validatePath:downloadPath withEncodedDSASignature:dsaSignature withPublicDSAKey:pkeyString])
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

#pragma mark Installation

- (IBAction)installAndRestart:sender
{
	NSString *newAppDownloadPath = nil;
	BOOL isPackage = NO;
	int processIdentifier = [[NSProcessInfo processInfo] processIdentifier];
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
				
		// Search subdirectories for the application
		NSString *file, *bundleFileName = [[hostBundle bundlePath] lastPathComponent];
		NSDirectoryEnumerator *dirEnum = [[NSFileManager defaultManager] enumeratorAtPath:[downloadPath stringByDeletingLastPathComponent]];
		while ((file = [dirEnum nextObject]))
		{
			// Some DMGs have symlinks into /Applications! That's no good!
			if ([file isEqualToString:@"/Applications"])
				[dirEnum skipDescendents];
			if ([[file lastPathComponent] isEqualToString:bundleFileName]) // We found one!
			{
				isPackage = NO;
				newAppDownloadPath = [[downloadPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:file];
				break;
			}
			else if (([[file pathExtension] isEqualToString:@"pkg"] || [[file pathExtension] isEqualToString:@"mpkg"]) &&
					 [[file stringByDeletingPathExtension] isEqualToString:[[[hostBundle bundlePath] lastPathComponent] stringByDeletingPathExtension]])
			{
				isPackage = YES;
				newAppDownloadPath = [[downloadPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:file];
				break;
			}
			if ([[file pathExtension] isEqualToString:[[hostBundle bundlePath] pathExtension]] ||
				[[file pathExtension] isEqualToString:@"pkg"] ||
				[[file pathExtension] isEqualToString:@"mpkg"]) // No point in looking in bundles.
			{
				[dirEnum skipDescendents];
			}
		}
		
		if (!newAppDownloadPath || ![[NSFileManager defaultManager] fileExistsAtPath:newAppDownloadPath])
		{
			[NSException raise:@"SUInstallException" format:@"The update archive didn't contain an application with the proper name: %@.", bundleFileName];
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
		if (!isPackage)
		{
			NSInteger tag = 0;
			BOOL result = [[NSWorkspace sharedWorkspace] performFileOperation:NSWorkspaceRecycleOperation source:[[hostBundle bundlePath] stringByDeletingLastPathComponent] destination:@"" files:[NSArray arrayWithObject:[[hostBundle bundlePath] lastPathComponent]] tag:&tag];
			result &= [[NSFileManager defaultManager] movePath:newAppDownloadPath toPath:[hostBundle bundlePath] handler:nil];
			if (!result)
			{
				[self abandonUpdate];
				return;
			}
		}
		else
		{
			NSString *installerPath = [[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier:@"com.apple.installer"];
			installerPath = [installerPath stringByAppendingString:@"/Contents/MacOS/Installer"];
			NSTask *installer = [NSTask launchedTaskWithLaunchPath:installerPath arguments:[NSArray arrayWithObjects:newAppDownloadPath, nil]];
			processIdentifier = [installer processIdentifier];
		}
	}
	else // But if we're updating by the action of the user, do an authenticated move.
	{
		if (isPackage)
		{
			NSString *installerPath = [[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier:@"com.apple.installer"];
			installerPath = [installerPath stringByAppendingString:@"/Contents/MacOS/Installer"];
			NSTask *installer = [NSTask launchedTaskWithLaunchPath:installerPath arguments:[NSArray arrayWithObjects:newAppDownloadPath, nil]];
			processIdentifier = [installer processIdentifier];
		}
		else
		{			
			if (![[NSFileManager defaultManager] copyPathWithAuthentication:newAppDownloadPath toPath:[hostBundle bundlePath]])
			{
				[self showUpdateErrorAlertWithInfo:[NSString stringWithFormat:SULocalizedString(@"%@ does not have permission to write to the application's directory! Are you running off a disk image? If not, ask your system administrator for help.", nil), [hostBundle name]]];
				[self abandonUpdate];
				return;
			}
		}
	}
	
	// Prompt for permission to restart if we're automatically updating.
	if ([self isAutomaticallyUpdating])
	{
		SUAutomaticUpdateAlert *alert = [[SUAutomaticUpdateAlert alloc] initWithAppcastItem:updateItem hostBundle:hostBundle];
		if ([NSApp runModalForWindow:[alert window]] == NSAlertAlternateReturn)
		{
			[alert release];
			return;
		}
	}
	
	// This is really sloppy and coupled, but gosh darn it, I'm not maintaining this codebase much longer. Sorry!
	// If we've got a DMG, we've mounted it; now we've got to unmount it.
	if ([[[downloadPath pathExtension] lowercaseString] isEqualToString:@"dmg"])
	{
		[NSTask launchedTaskWithLaunchPath:@"/usr/bin/hdiutil" arguments:[NSArray arrayWithObjects:@"detach", [newAppDownloadPath stringByDeletingLastPathComponent], @"-force", nil]];	
	}
	
	[[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterWillRestartNotification object:self];
	
	NSString *relaunchPath = [[[NSBundle bundleForClass:[self class]] executablePath] stringByDeletingLastPathComponent];
	if (!relaunchPath) // slight hack to resolve issues with running within bundles
	{
		NSString *frameworkPath = [[[NSBundle mainBundle] sharedFrameworksPath] stringByAppendingPathComponent:@"Sparkle.framework"];
		NSBundle *framework = [NSBundle bundleWithPath:frameworkPath];
		relaunchPath = [[framework executablePath] stringByDeletingLastPathComponent];
	}
	relaunchPath = [relaunchPath stringByAppendingPathComponent:@"relaunch.app/Contents/MacOS/relaunch"];
	
	[NSTask launchedTaskWithLaunchPath:relaunchPath arguments:[NSArray arrayWithObjects:[hostBundle bundlePath], [NSString stringWithFormat:@"%d", processIdentifier], nil]];
	[NSApp terminate:self];
}

#pragma mark Error handling

- (void)showUpdateErrorAlertWithInfo:(NSString *)info
{
	if ([self isAutomaticallyUpdating]) { return; }
	NSAlert *alert = [NSAlert alertWithMessageText:SULocalizedString(@"Update Error!", nil) defaultButton:SULocalizedString(@"Cancel Update", nil) alternateButton:nil otherButton:nil informativeTextWithFormat:info];
	[alert setIcon:[hostBundle icon]];
	[alert runModal];
}

- (void)abandonUpdate
{
	if (updateItem) { [updateItem autorelease]; }
	updateItem = nil;
	if (statusController)
	{
		[statusController close];
		[statusController autorelease];
	}
	statusController = nil;
	updateInProgress = NO;
	[self scheduleCheckWithInterval:checkInterval];
}

- (void)dealloc
{
	[updateItem release];
	[downloader release];	
	[downloadPath release];
	[statusController release];
	[hostBundle release];	
	if (checkTimer) { [checkTimer invalidate]; }
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[super dealloc];
}

@end
