//
//  SUScheduledUpdateDriver.m
//  Sparkle
//
//  Created by Andy Matuschak on 5/6/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUScheduledUpdateDriver.h"
#import "Sparkle.h"

@implementation SUScheduledUpdateDriver

- (BOOL)itemContainsValidUpdate:(SUAppcastItem *)ui
{
	// I wish I could think of a good way to not duplicate this code from SUBasicUpdateDriver, but inheritance makes it tricky.
	return [self hostSupportsItem:ui] && [self isItemNewer:ui] && ![self itemContainsSkippedVersion:ui];
}

- (void)didFindValidUpdate
{
	showErrors = YES; // We only start showing errors after we present the UI for the first time.
	[super didFindValidUpdate];
}

- (void)didNotFindUpdate
{
	[self abortUpdate]; // Don't tell the user that no update was found; this was a scheduled update.
}

- (void)abortUpdateWithError:(NSError *)error
{
	if (showErrors)
		[super abortUpdateWithError:error];
	else
		[self abortUpdate];
}

@end
