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
	[items release];
	[super dealloc];
}

- (NSArray *)items
{
	return items;
}

- (void)fetchAppcastFromURL:(NSURL *)url
{
	RSS *feed = [[RSS alloc] initWithURL:url userAgent:userAgentString delegate:self];
	CFRetain(feed); // Manage the RSS feed's memory manually.
}

- (void)feedDidFinishLoading:(RSS *)feed
{
	// Set up all the appcast items:
	NSArray *tempItems = [NSMutableArray array];
	id enumerator = [[feed newsItems] objectEnumerator], current;
	@try
	{
		while ((current = [enumerator nextObject]))
		{
			[(NSMutableArray *)tempItems addObject:[[[SUAppcastItem alloc] initWithDictionary:current] autorelease]];
		}
		items = [[NSArray arrayWithArray:tempItems] retain]; // Make the items list immutable.
		
		if ([delegate respondsToSelector:@selector(appcastDidFinishLoading:)])
			[delegate performSelectorOnMainThread:@selector(appcastDidFinishLoading:) withObject:self waitUntilDone:NO];		
	}
	@catch (NSException *parseException)
	{
		[self reportError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUAppcastParseError userInfo:[NSDictionary dictionaryWithObjectsAndKeys:SULocalizedString(@"An error occurred while parsing the update feed.", nil), NSLocalizedDescriptionKey, [parseException reason], SUTechnicalErrorInformationKey, nil]]];
	}
	CFRelease(feed);
}

- (void)feed:(RSS *)feed didFailWithError:(NSError *)error
{
	[self reportError:error];
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
	[userAgentString release];
	userAgentString = [uas copy];
}

- (void)setDelegate:del
{
	delegate = del;
}

@end
