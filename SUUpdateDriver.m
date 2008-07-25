//
//  SUUpdateDriver.m
//  Sparkle
//
//  Created by Andy Matuschak on 5/7/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUUpdateDriver.h"

NSString *SUUpdateDriverFinishedNotification = @"SUUpdateDriverFinished";

@implementation SUUpdateDriver
- (void)checkForUpdatesAtURL:(NSURL *)appcastURL host:(SUHost *)h
{
	host = [h retain];
}

- (void)abortUpdate
{
	[self setValue:[NSNumber numberWithBool:YES] forKey:@"finished"];	
	[[NSNotificationCenter defaultCenter] postNotificationName:SUUpdateDriverFinishedNotification object:self];
}

- (BOOL)finished { return finished; }
@end
