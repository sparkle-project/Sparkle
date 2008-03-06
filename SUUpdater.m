//
//  SUUpdater.m
//  Sparkle
//
//  Created by Andy Matuschak on 1/4/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import "Sparkle.h"
#import "SUUpdater.h"

#import <stdio.h>
#import <sys/stat.h>
#import <unistd.h>
#import <signal.h>
#import <dirent.h>

@interface SUUpdater (Private)
- (void)beginUpdateCheck;
- (void)beginUpdateCycle;
- (void)showUpdateAlert;
- (void)beginDownload;
- (void)extractUpdate;
- (void)showUpdateErrorAlertWithInfo:(NSString *)info;
- (void)abandonUpdate;
- (IBAction)installAndRestart:sender;
@end

@implementation SUUpdater

#pragma mark Initialization

static SUUpdater *sharedUpdater = nil;

// SUUpdater's a singleton now! And I'm enforcing it!
// This will probably break the world if you try to write a Sparkle-enabled plugin for a Sparkle-enabled app.
+ (SUUpdater *)sharedUpdater
{
	if (sharedUpdater == nil)
		sharedUpdater = [[[self class] alloc] init];
	return sharedUpdater;
}

- (id)init
{
	self = [super init];
	if (sharedUpdater)
	{
		[self release];
		self = sharedUpdater;
	}
	else if (self != nil)
	{
		sharedUpdater = self;
		[self setHostBundle:[NSBundle mainBundle]];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidFinishLaunching:) name:NSApplicationDidFinishLaunchingNotification object:NSApp];
	}
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
		
		[SUUpdatePermissionPrompt promptWithHostBundle:hostBundle delegate:self];
	}
	
	if ([[SUUserDefaults standardUserDefaults] boolForKey:SUEnableAutomaticChecksKey] == YES)
		[self beginUpdateCycle];
}

- (void)updatePermissionPromptFinishedWithResult:(SUPermissionPromptResult)result
{
	BOOL automaticallyUpdate = (result == SUAutomaticallyUpdate);
	[[SUUserDefaults standardUserDefaults] setBool:(result == SUAutomaticallyUpdate) forKey:SUEnableAutomaticChecksKey];
	if (automaticallyUpdate)
		[self beginUpdateCycle];
}

- (void)beginUpdateCycle
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
	if (intervalSinceCheck < checkInterval)
		delayUntilCheck = (checkInterval - intervalSinceCheck); // It hasn't been long enough.
	else
		delayUntilCheck = 0; // We're overdue! Run one now.
	
	[self performSelector:@selector(checkForUpdatesInBackground) withObject:nil afterDelay:delayUntilCheck];
	[self performSelector:@selector(scheduleCheckWithIntervalObject:) withObject:[NSNumber numberWithDouble:checkInterval] afterDelay:delayUntilCheck];	
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

- (NSArray *)feedParameters
{
	BOOL sendingSystemProfile = ([[SUUserDefaults standardUserDefaults] boolForKey:SUSendProfileInfoKey] == YES);
	NSArray *parameters = [NSArray array];
	if ([delegate respondsToSelector:@selector(feedParametersForUpdater:sendingSystemProfile:)])
		parameters = [parameters arrayByAddingObjectsFromArray:[delegate feedParametersForUpdater:self sendingSystemProfile:sendingSystemProfile]];
	if (sendingSystemProfile)
		parameters = [parameters arrayByAddingObjectsFromArray:[hostBundle systemProfile]];
	return parameters;
}

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
	NSString *appcastString = [[SUUserDefaults standardUserDefaults] objectForKey:SUFeedURLKey];	// if URL is quoted (because of pre-processing in plist files), remove quotes from the string
	if (!appcastString)
		appcastString = [hostBundle objectForInfoDictionaryKey:SUFeedURLKey];
	if (!appcastString)
		[NSException raise:@"SUNoFeedURL" format:@"You must specify the URL of the appcast as the SUFeedURLKey in either the Info.plist or the user defaults!"];
	
	NSCharacterSet* quoteSet = [NSCharacterSet characterSetWithCharactersInString: @"\"\'"];
	SUAppcast *appcast = [[SUAppcast alloc] init];
	[appcast setDelegate:self];
	[appcast fetchAppcastFromURL:[NSURL URLWithString:[appcastString stringByTrimmingCharactersInSet:quoteSet]] parameters:[self feedParameters]];
}

- (BOOL)newVersionAvailable
{
	// We also have to make sure that the newest version can run on the user's system.
	id <SUVersionComparison> comparator = [SUStandardVersionComparator defaultComparator];
	BOOL canRunOnCurrentSystem = ([comparator compareVersion:[updateItem minimumSystemVersion] toVersion:[SUUpdater systemVersionString]] != NSOrderedDescending);
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
	statusController = [[SUStatusController alloc] initWithHostBundle:hostBundle];
	[statusController beginActionWithTitle:SULocalizedString(@"Downloading update...", nil) maxProgressValue:0 statusText:nil];
	[statusController setButtonTitle:SULocalizedString(@"Cancel", nil) target:self action:@selector(cancelDownload:) isDefault:NO];
	if ([self isAutomaticallyUpdating] == NO)
		[statusController showWindow:self];
	
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
	[statusController beginActionWithTitle:SULocalizedString(@"Installing update...", nil) maxProgressValue:0 statusText:nil];
	[statusController setButtonEnabled:NO];
	
	// Hack to force us to wait for the UI to update.
	NSEvent *event;
	while((event = [NSApp nextEventMatchingMask:NSAnyEventMask untilDate:nil inMode:NSDefaultRunLoopMode dequeue:YES]))
		[NSApp sendEvent:event];	

	// Search subdirectories for the application
	NSString *currentFile, *newAppDownloadPath = nil, *bundleFileName = [[hostBundle bundlePath] lastPathComponent];
	BOOL isPackage = NO;
	NSDirectoryEnumerator *dirEnum = [[NSFileManager defaultManager] enumeratorAtPath:[downloadPath stringByDeletingLastPathComponent]];
	while ((currentFile = [dirEnum nextObject]))
	{
		// Some DMGs have symlinks into /Applications! That's no good! And there's no point in looking in bundles.
		if ([[NSFileManager defaultManager] isAliasFolderAtPath:[[downloadPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:currentFile]] ||
			[[currentFile pathExtension] isEqualToString:[[hostBundle bundlePath] pathExtension]] ||
			[[currentFile pathExtension] isEqualToString:@"pkg"] ||
			[[currentFile pathExtension] isEqualToString:@"mpkg"])
		{
			[dirEnum skipDescendents];
		}
		
		if ([[currentFile lastPathComponent] isEqualToString:bundleFileName]) // We found one!
		{
			isPackage = NO;
			newAppDownloadPath = [[downloadPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:currentFile];
			break;
		}
		else if (([[currentFile pathExtension] isEqualToString:@"pkg"] || [[currentFile pathExtension] isEqualToString:@"mpkg"]) &&
				  [[[currentFile lastPathComponent] stringByDeletingPathExtension] isEqualToString:[bundleFileName stringByDeletingPathExtension]])
		{
			isPackage = YES;
			newAppDownloadPath = [[downloadPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:currentFile];
			break;
		}
	}
	
	if (![[NSFileManager defaultManager] fileExistsAtPath:newAppDownloadPath])
	{
		NSLog(@"The update archive didn't contain an application or package with the proper name: %@ or %@.", bundleFileName, [[bundleFileName stringByDeletingPathExtension] stringByAppendingPathComponent:@".[m]pkg"]);
		[self showUpdateErrorAlertWithInfo:SULocalizedString(@"An error occurred during installation. Please try again later.", nil)];
		[self abandonUpdate];
		return;		
	}
	
	// Now that we've found the path we care about, let's install it.
	
	// But before we do that, we need to copy out relaunch.app so we can run it later.
	NSString *relaunchPath = [[[NSBundle bundleForClass:[self class]] executablePath] stringByDeletingLastPathComponent];
	if (!relaunchPath) // Slight hack to resolve issues with running within bundles
	{
		NSString *frameworkPath = [[[NSBundle mainBundle] sharedFrameworksPath] stringByAppendingPathComponent:@"Sparkle.framework"];
		NSBundle *framework = [NSBundle bundleWithPath:frameworkPath];
		relaunchPath = [[framework executablePath] stringByDeletingLastPathComponent];
	}
	relaunchPath = [relaunchPath stringByAppendingPathComponent:@"relaunch.app/Contents/MacOS/relaunch"];
	NSString *newRelaunchPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"relaunch"];
	[[NSFileManager defaultManager] copyPath:relaunchPath toPath:newRelaunchPath handler:nil];
	
	// Alright, *now* we can actually install the new version.
	int processIdentifierToWatch = [[NSProcessInfo processInfo] processIdentifier];
	if (isPackage)
	{
		NSString *installerPath = [[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier:@"com.apple.installer"];
		installerPath = [installerPath stringByAppendingString:@"/Contents/MacOS/Installer"];
		NSTask *installer = [NSTask launchedTaskWithLaunchPath:installerPath arguments:[NSArray arrayWithObjects:newAppDownloadPath, nil]];
		processIdentifierToWatch = [installer processIdentifier]; // We want to wait until the installer quits.
	}
	else
	{
		if (![[NSFileManager defaultManager] copyPath:newAppDownloadPath
											 overPath:[hostBundle bundlePath]
								   withAuthentication:![self isAutomaticallyUpdating]])
		{
			[self showUpdateErrorAlertWithInfo:[NSString stringWithFormat:SULocalizedString(@"%@ can't install the update! Make sure you have enough disk space.", nil), [hostBundle name]]];
			[self abandonUpdate];
			return;
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
	
	// This is really sloppy and coupled, but I can't think of a better way to deal with this.
	// If we've got a DMG, we've mounted it; now we've got to unmount it.
	if ([[[downloadPath pathExtension] lowercaseString] isEqualToString:@"dmg"])
	{
		[NSTask launchedTaskWithLaunchPath:@"/usr/bin/hdiutil" arguments:[NSArray arrayWithObjects:@"detach", [newAppDownloadPath stringByDeletingLastPathComponent], @"-force", nil]];	
	}
	
	[[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterWillRestartNotification object:self];
		
	[NSTask launchedTaskWithLaunchPath:newRelaunchPath arguments:[NSArray arrayWithObjects:[hostBundle bundlePath], [NSString stringWithFormat:@"%d", processIdentifierToWatch], nil]];
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
	[delegate release];
	if (checkTimer) { [checkTimer invalidate]; }
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[super dealloc];
}

+ (NSString *)systemVersionString
{
	// This returns a version string of the form X.Y.Z
	// There may be a better way to deal with the problem that gestaltSystemVersionMajor
	//  et al. are not defined in 10.3, but this is probably good enough.
	NSString* verStr = nil;
#if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_4
	SInt32 major, minor, bugfix;
	OSErr err1 = Gestalt(gestaltSystemVersionMajor, &major);
	OSErr err2 = Gestalt(gestaltSystemVersionMinor, &minor);
	OSErr err3 = Gestalt(gestaltSystemVersionBugFix, &bugfix);
	if (!err1 && !err2 && !err3)
	{
		verStr = [NSString stringWithFormat:@"%d.%d.%d", major, minor, bugfix];
	}
	else
#endif
	{
	 	NSString *versionPlistPath = @"/System/Library/CoreServices/SystemVersion.plist";
		verStr = [[[NSDictionary dictionaryWithContentsOfFile:versionPlistPath] objectForKey:@"ProductVersion"] retain];
	}
	return verStr;
}

- (void)setDelegate:aDelegate
{
	[delegate release];
	delegate = [aDelegate retain];
}

@end
