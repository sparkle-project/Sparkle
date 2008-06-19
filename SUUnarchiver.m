//
//  SUUnarchiver.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/16/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//


#import "Sparkle.h"
#import "SUUnarchiver.h"
#import "SUUnarchiver_Private.h"

@implementation SUUnarchiver

extern NSMutableArray *__unarchiverImplementations;

+ (SUUnarchiver *)unarchiverForURL:(NSURL *)URL
{
	NSEnumerator *implementationEnumerator = [[self _unarchiverImplementations] objectEnumerator];
	id current;
	while ((current = [implementationEnumerator nextObject]))
	{
		if ([current _canUnarchiveURL:URL])
			return [[[current alloc] _initWithURL:URL] autorelease];
	}
	return nil;
}

- (void)setDelegate:del
{
	delegate = del;
}

- (void)start
{
	// No-op
}

@end
