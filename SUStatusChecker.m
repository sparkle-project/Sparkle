//
//  SUStatusChecker.m
//  Sparkle
//
//  Created by Evan Schoenberg on 7/6/06.
//

#import "SUStatusChecker.h"
#import "SUAppcast.h"
#import "SUAppcastItem.h"

@interface SUStatusChecker (Private)
- (id)initForDelegate:(id<SUStatusCheckerDelegate>)inDelegate;
- (void)checkForUpdatesAndNotify:(BOOL)verbosity;
- (BOOL)newVersionAvailable;
@end;

@implementation SUStatusChecker

+ (SUStatusChecker *)statusCheckerForDelegate:(id<SUStatusCheckerDelegate>)inDelegate;
{
	SUStatusChecker *statusChecker = [[self alloc] initForDelegate:inDelegate];

	return [statusChecker autorelease];
}

- (id)initForDelegate:(id<SUStatusCheckerDelegate>)inDelegate
{
	[super init];

	scDelegate = [inDelegate retain];

	[self checkForUpdatesAndNotify:NO];

	return self;
}

- (void)dealloc
{
	[scDelegate release]; scDelegate = nil;
	
	[super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
	//Take no action when the application finishes launching
}

- (void)appcastDidFinishLoading:(SUAppcast *)ac
{
	@try
	{
		if (!ac) { [NSException raise:@"SUAppcastException" format:@"Couldn't get a valid appcast from the server."]; }
		
		updateItem = [[ac newestItem] retain];
		[ac autorelease];
		
		if (![updateItem fileVersion])
		{
			[NSException raise:@"SUAppcastException" format:@"Can't extract a version string from the appcast feed. The filenames should look like YourApp_1.5.tgz, where 1.5 is the version number."];
		}

		[scDelegate statusChecker:self
					 foundVersion:[updateItem fileVersion]
					 isNewVersion:[self newVersionAvailable]];
	}
	@catch (NSException *e)
	{
		NSLog([e reason]);

		[scDelegate statusChecker:self foundVersion:nil isNewVersion:NO];	
	}

	updateInProgress = NO;
}

@end
