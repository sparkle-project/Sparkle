//
//  SUAppcast.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/12/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import "Sparkle.h"
#import "SUAppcast.h"

@interface SUAppcast (Private)
- (void)reportError:(NSError *)error;
@end

@implementation SUAppcast

- (void)dealloc
{
	[feed release];
	[items release];
	[super dealloc];
}

- (NSArray *)items
{
	return items;
}

- (void)fetchAppcastFromURL:(NSURL *)url
{
	feed = [[RSS alloc] initWithURL:url userAgent:userAgentString delegate:self];
}

- (void)feedDidFinishLoading:(RSS *)aFeed
{
	// Set up all the appcast items:
	NSArray *tempItems = [NSMutableArray array];
	id enumerator = [[feed newsItems] objectEnumerator], current;
    BOOL success = YES;
    while ((current = [enumerator nextObject]))
    {
        SUAppcastItem *item = [[[SUAppcastItem alloc] initWithDictionary:current] autorelease];
        if (item)
        {
            [(NSMutableArray *)tempItems addObject:item];
        }
        else
        {
            success = NO;
            break;
        }
    }
	if (success)
	{
        items = [tempItems copy]; // Make the items list immutable.
        
        if ([delegate respondsToSelector:@selector(appcastDidFinishLoading:)])
            [delegate performSelectorOnMainThread:@selector(appcastDidFinishLoading:) withObject:self waitUntilDone:NO];		
    }
    else
    {
		[self reportError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUAppcastParseError userInfo:[NSDictionary dictionaryWithObjectsAndKeys:SULocalizedString(@"An error occurred while parsing the update feed.", nil), NSLocalizedDescriptionKey, nil]]];
	}
	[feed release];
    feed = nil;
}

- (void)feed:(RSS *)aFeed didFailWithError:(NSError *)error
{
	[self reportError:error];
	[feed release];
    feed = nil;
}

- (void)reportError:(NSError *)error
{
	if ([delegate respondsToSelector:@selector(appcast:failedToLoadWithError:)])
	{
		[delegate appcast:self failedToLoadWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUAppcastError userInfo:[NSDictionary dictionaryWithObjectsAndKeys:SULocalizedString(@"An error occurred in retrieving update information. Please try again later.", nil), NSLocalizedDescriptionKey, [error localizedDescription], NSLocalizedFailureReasonErrorKey, nil]]];
	}
}

- (void)setUserAgentString:(NSString *)uas
{
	if (uas != userAgentString)
	{
		[userAgentString release];
		userAgentString = [uas copy];
	}
}

- (void)setDelegate:del
{
	delegate = del;
}

@end
