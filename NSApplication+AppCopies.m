//
//  NSApplication+AppCopies.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/16/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import "NSApplication+AppCopies.h"
#import "SUUtilities.h"

@implementation NSApplication (SUAppCopies)

- (int)copiesRunning
{
	id appEnumerator = [[[NSWorkspace sharedWorkspace] launchedApplications] objectEnumerator], currentApp;
	int count = 0;
	while ((currentApp = [appEnumerator nextObject]))
	{
		// Potential gotcha: the new version of your app better have the same NSApplicationName.
		if([[currentApp objectForKey:@"NSApplicationName"] isEqualToString:SUHostAppName()])
			count++;
	}
	return count;	
}

@end
