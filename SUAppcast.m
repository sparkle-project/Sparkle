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
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:30.0];
    if (userAgentString)
        [request setValue:userAgentString forHTTPHeaderField:@"User-Agent"];
            
    incrementalData = [[NSMutableData alloc] init];
    NSURLConnection *connection = [NSURLConnection connectionWithRequest:request delegate:self];
    CFRetain(connection);
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
	[incrementalData appendData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
	CFRelease(connection);
    
	NSError *error = nil;
    NSXMLDocument *document = [[NSXMLDocument alloc] initWithData:incrementalData options:0 error:&error];
	BOOL failed = NO;
	NSArray *xmlItems = nil;
	NSMutableArray *appcastItems = [NSMutableArray array];
	
    if (nil == document)
    {
        failed = YES;
    }
    else
    {
        xmlItems = [document nodesForXPath:@"/rss/channel/item" error:&error];
        if (nil == xmlItems)
        {
            failed = YES;
        }
    }
    
	if (failed == NO)
    {
		
		NSEnumerator *nodeEnum = [xmlItems objectEnumerator];
		NSXMLNode *node;
		NSMutableDictionary *dict = [NSMutableDictionary dictionary];
		
		while (failed == NO && (node = [nodeEnum nextObject]))
        {
			// walk the children in reverse
			node = [[node children] lastObject];
			while (nil != node)
            {
				
				NSString *name = [node name];
				
				if ([name isEqualToString:@"enclosure"]) {
					// enclosure is flattened as a separate dictionary for some reason
					NSEnumerator *attributeEnum = [[(NSXMLElement *)node attributes] objectEnumerator];
					NSXMLNode *attribute;
					NSMutableDictionary *encDict = [NSMutableDictionary dictionary];
					
					while ((attribute = [attributeEnum nextObject]))
                    {
						[encDict setObject:[attribute stringValue] forKey:[attribute name]];
					}
					[dict setObject:encDict forKey:@"enclosure"];
					
				}
                else if ([name isEqualToString:@"pubDate"])
                {
					// pubDate is expected to be an NSDate by SUAppcastItem, but the RSS class was returning an NSString
					NSDate *date = [NSDate dateWithNaturalLanguageString:[node stringValue]];
					if (date)
						[dict setObject:date forKey:name];
				}
                else if (name != nil)
                {
					// add all other values as strings
					[dict setObject:[[node stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] forKey:name];
				}
				
				// previous sibling; returns nil when exhausted
				node = [node previousSibling];
			}
			SUAppcastItem *anItem = [[SUAppcastItem alloc] initWithDictionary:dict];
            if (anItem)
            {
                [appcastItems addObject:anItem];
                [anItem release];
			}
            else
            {
				NSLog(@"Sparkle Updater: Failed to parse appcast item with appcast dictionary %@!", dict);
            }
            [dict removeAllObjects];
		}
	}
    
	[document release];
	
	if ([appcastItems count])
    {
		NSSortDescriptor *sort = [[[NSSortDescriptor alloc] initWithKey:@"date" ascending:NO] autorelease];
		[appcastItems sortUsingDescriptors:[NSArray arrayWithObject:sort]];
		items = [appcastItems copy];
	}
	
	if (failed)
    {
        [self reportError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUAppcastParseError userInfo:[NSDictionary dictionaryWithObjectsAndKeys:SULocalizedString(@"An error occurred while parsing the update feed.", nil), NSLocalizedDescriptionKey, nil]]];
	}
    else if ([delegate respondsToSelector:@selector(appcastDidFinishLoading:)])
    {
        [delegate appcastDidFinishLoading:self];
	}
}

- (void)connection:(NSURLConnection*)connection didFailWithError:(NSError *)error
{
	CFRelease(connection);
    
	[self reportError:error];
}

- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)redirectResponse
{
	return request;
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
