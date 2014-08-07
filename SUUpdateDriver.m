//
//  SUUpdateDriver.m
//  Sparkle
//
//  Created by Andy Matuschak on 5/7/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUUpdateDriver.h"
#import "SUHost.h"

NSString * const SUUpdateDriverFinishedNotification = @"SUUpdateDriverFinished";

@implementation SUUpdateDriver
- initWithUpdater:(SUUpdater *)anUpdater
{
	if ((self = [super init]))
		updater = anUpdater;
	return self;
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@, %@>", [self class], [host bundlePath], [host installationPath]]; }

- (void)checkForUpdatesAtURL:(NSURL *)URL host:(SUHost *)h
{
    abortReason = SUUpdateAbortUndefined;
	appcastURL = [URL copy];
	host = [h retain];
}

- (void)abortUpdate:(SUUpdateAbortReason)reason
{
    abortReason = reason;
	[[NSNotificationCenter defaultCenter] postNotificationName:SUUpdateDriverFinishedNotification object:self];
}

- (BOOL)finished
{
    return abortReason != SUUpdateAbortUndefined;
}

- (SUUpdateAbortReason)abortReason
{
    return abortReason;
}

- (BOOL)shouldShowUI
{
    return NO;
}

- (void)dealloc
{
    [host release];
	[appcastURL release];
    [super dealloc];
}

- (SUHost*)host
{
    return host;
}

- (void)setHost:(SUHost*)newHost
{
    [host release];
    host = [newHost retain];
}

@end
