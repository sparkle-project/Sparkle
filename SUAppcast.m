//
//  SUAppcast.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/12/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import "Sparkle.h"
#import "SUAppcast.h"

@implementation SUAppcast

- (void)fetchAppcastFromURL:(NSURL *)url
{
	[NSThread detachNewThreadSelector:@selector(_fetchAppcastFromURL:) toTarget:self withObject:url];
}

- (void)dealloc
{
	[items release];
	[super dealloc];
}

- (NSArray *)items
{
	return items;
}

- (void)_fetchAppcastFromURL:(NSURL *)url
{
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
	
	NSError *error = nil;
	RSS *feed = [[RSS alloc] initWithURL:url normalize:YES userAgent:userAgentString error:&error];
	if (!feed)
	{
		[self performSelectorOnMainThread:@selector(reportError:) withObject:error waitUntilDone:NO];
		return;
	}
		
	// Set up all the appcast items:
	items = [NSMutableArray array];
	id enumerator = [[feed newsItems] objectEnumerator], current;
	@try
	{
		while ((current = [enumerator nextObject]))
		{
			[(NSMutableArray *)items addObject:[[[SUAppcastItem alloc] initWithDictionary:current] autorelease]];
		}
	}
	@catch (NSException *parseException)
	{
		error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUAppcastParseError userInfo:[NSDictionary dictionaryWithObjectsAndKeys:SULocalizedString(@"An error occurred while parsing the update feed.", nil), NSLocalizedDescriptionKey, [parseException reason], SUTechnicalErrorInformationKey, nil]];
		[self performSelectorOnMainThread:@selector(reportError:) withObject:error waitUntilDone:NO];
		return;
	}
	items = [[NSArray arrayWithArray:items] retain]; // Make the items list immutable.
	
	if ([delegate respondsToSelector:@selector(appcastDidFinishLoading:)])
		[delegate performSelectorOnMainThread:@selector(appcastDidFinishLoading:) withObject:self waitUntilDone:NO];
		
	[feed release];
	[pool release];
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
