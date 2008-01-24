//
//  SUAppcast.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/12/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import "Sparkle.h"
#import "SUAppcast.h"

@interface NSURL (SUParameterAdditions)
- (NSURL *)URLWithParameters:(NSArray *)parameters;
@end

@implementation NSURL (SUParameterAdditions)
- (NSURL *)URLWithParameters:(NSArray *)parameters;
{
	if (parameters == nil || [parameters count] == 0) { return self; }
	NSMutableArray *profileInfo = [NSMutableArray array];
	NSEnumerator *profileInfoEnumerator = [parameters objectEnumerator];
	NSDictionary *currentProfileInfo;
	while ((currentProfileInfo = [profileInfoEnumerator nextObject])) {
		[profileInfo addObject:[NSString stringWithFormat:@"%@=%@", [currentProfileInfo objectForKey:@"key"], [currentProfileInfo objectForKey:@"value"]]];
	}
	
	NSString *appcastStringWithProfile = [NSString stringWithFormat:@"%@?%@", [self absoluteString], [profileInfo componentsJoinedByString:@"&"]];
	
	// Clean it up so it's a valid URL
	return [NSURL URLWithString:[appcastStringWithProfile stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
}
@end


@implementation SUAppcast

- (void)fetchAppcastFromURL:(NSURL *)url parameters:(NSArray *)parameters
{
	[NSThread detachNewThreadSelector:@selector(_fetchAppcastFromURL:) toTarget:self withObject:[url URLWithParameters:parameters]]; // let's not block the main thread
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
	
	RSS *feed = [RSS alloc];
	@try
	{
		NSString *userAgent = nil;
		if ([delegate respondsToSelector:@selector(userAgentForAppcast:)])
			userAgent = [delegate userAgentForAppcast:self];
		
		feed = [feed initWithURL:url normalize:YES userAgent:userAgent];
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
		[feed release];
		[pool release];	
	}
}

@end
