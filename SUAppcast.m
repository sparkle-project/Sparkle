//
//  SUAppcast.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/12/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import "SUAppcast.h"
#import "SUAppcastItem.h"
#import "SUUtilities.h"
#import "RSS.h"

@implementation SUAppcast

- (void)fetchAppcastFromURL:(NSURL *)url
{
	[NSThread detachNewThreadSelector:@selector(_fetchAppcastFromURL:) toTarget:self withObject:url]; // let's not block the main thread
}

- (void)setDelegate:del
{
	delegate = del;
}

- (void)dealloc
{
	[items release];
	[super dealloc];
}

- (SUAppcastItem *)newestItem
{
	return [items objectAtIndex:0]; // the RSS class takes care of sorting by published date, descending.
}

- (NSArray *)items
{
	return items;
}

- (void)_fetchAppcastFromURL:(NSURL *)url
{
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
	
	RSS *feed;
	@try
	{
		NSString *userAgent = [NSString stringWithFormat: @"%@/%@ (Mac OS X) Sparkle/1.1", SUHostAppName(), SUHostAppVersion()];
		
		feed = [[RSS alloc] initWithURL:url normalize:YES userAgent:userAgent];
		if (!feed)
			[NSException raise:@"SUFeedException" format:@"Couldn't fetch feed from server."];
		
		// Set up all the appcast items
		NSMutableArray *tempItems = [NSMutableArray array];
		id enumerator = [[feed newsItems] objectEnumerator], current;
		while ((current = [enumerator nextObject]))
		{
			[tempItems addObject:[[[SUAppcastItem alloc] initWithDictionary:current] autorelease]];
		}
		items = [[NSArray arrayWithArray:tempItems] retain];
		[feed release];
		
		if ([delegate respondsToSelector:@selector(appcastDidFinishLoading:)])
			[delegate performSelectorOnMainThread:@selector(appcastDidFinishLoading:) withObject:self waitUntilDone:NO];
		
	}
	@catch (NSException *e)
	{
		if ([delegate respondsToSelector:@selector(appcastDidFailToLoad:)])
			[delegate performSelectorOnMainThread:@selector(appcastDidFailToLoad:) withObject:self waitUntilDone:NO];
	}
	@finally
	{
		[pool release];	
	}
}

@end
