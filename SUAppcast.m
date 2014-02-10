//
//  SUAppcast.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/12/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import "SUUpdater.h"

#import "SUAppcast.h"
#import "SUAppcastItem.h"
#import "SUVersionComparisonProtocol.h"
#import "SUAppcast.h"
#import "SUConstants.h"
#import "SULog.h"

@interface NSXMLElement (SUAppcastExtensions)
- (NSDictionary *)attributesAsDictionary;
@end

@implementation NSXMLElement (SUAppcastExtensions)
- (NSDictionary *)attributesAsDictionary
{
	NSEnumerator *attributeEnum = [[self attributes] objectEnumerator];
	NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];

	for (NSXMLNode *attribute in attributeEnum) {
		[dictionary setObject:[attribute stringValue] forKey:[attribute name]];
	}
	return dictionary;
}
@end

@interface SUAppcast () <NSURLDownloadDelegate>
@property (copy) NSString *downloadFilename;
@property (retain) NSURLDownload *download;
@property (copy) NSArray *items;
- (void)reportError:(NSError *)error;
- (NSXMLNode *)bestNodeInNodes:(NSArray *)nodes;
@end

@implementation SUAppcast
@synthesize downloadFilename;
@synthesize delegate;
@synthesize userAgentString;
@synthesize download;
@synthesize items;

- (void)dealloc
{
	self.items = nil;
	self.userAgentString = nil;
	self.downloadFilename = nil;
	self.download = nil;
	
	[super dealloc];
}

- (void)fetchAppcastFromURL:(NSURL *)url
{
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:30.0];
    if (userAgentString)
        [request setValue:userAgentString forHTTPHeaderField:@"User-Agent"];
            
    self.download = [[[NSURLDownload alloc] initWithRequest:request delegate:self] autorelease];
}

- (void)download:(NSURLDownload *)aDownload decideDestinationWithSuggestedFilename:(NSString *)filename
{
	NSString* destinationFilename = NSTemporaryDirectory();
	if (destinationFilename)
	{
		destinationFilename = [destinationFilename stringByAppendingPathComponent:filename];
		[download setDestination:destinationFilename allowOverwrite:NO];
	}
}

- (void)download:(NSURLDownload *)aDownload didCreateDestination:(NSString *)path
{
    self.downloadFilename = path;
}

- (void)downloadDidFinish:(NSURLDownload *)aDownload
{    
	NSError *error = nil;
	
	NSXMLDocument *document = nil;
	BOOL failed = NO;
	NSArray *xmlItems = nil;
	NSMutableArray *appcastItems = [NSMutableArray array];
	
	if (downloadFilename)
	{
        NSUInteger options = 0;
        if (NSAppKitVersionNumber < NSAppKitVersionNumber10_7) {
            // In order to avoid including external entities when parsing the appcast (a potential security vulnerability; see https://github.com/andymatuschak/Sparkle/issues/169), we ask NSXMLDocument to "tidy" the XML first. This happens to remove these external entities; it wouldn't be a future-proof approach, but it worked in these historical versions of OS X, and we have a more rigorous approach for 10.7+.
            options = NSXMLDocumentTidyXML;
        } else {
            // In 10.7 and later, there's a real option for the behavior we desire.
            options = NSXMLNodeLoadExternalEntitiesSameOriginOnly;
        }
		document = [[[NSXMLDocument alloc] initWithContentsOfURL:[NSURL fileURLWithPath:downloadFilename] options:options error:&error] autorelease];
	
		[[NSFileManager defaultManager] removeItemAtPath:downloadFilename error:nil];
		self.downloadFilename = nil;
	}
	else
	{
		failed = YES;
	}
    
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
		NSMutableDictionary *nodesDict = [NSMutableDictionary dictionary];
		NSMutableDictionary *dict = [NSMutableDictionary dictionary];
		
		while (failed == NO && (node = [nodeEnum nextObject]))
        {
			// First, we'll "index" all the first-level children of this appcast item so we can pick them out by language later.
            if ([[node children] count])
            {
                node = [node childAtIndex:0];
                while (nil != node)
                {
                    NSString *name = [node name];
                    if (name)
                    {
                        NSMutableArray *nodes = [nodesDict objectForKey:name];
                        if (nodes == nil)
                        {
                            nodes = [NSMutableArray array];
                            [nodesDict setObject:nodes forKey:name];
                        }
                        [nodes addObject:node];
                    }
                    node = [node nextSibling];
                }
            }
            
            for (NSString *name in nodesDict)
            {
                node = [self bestNodeInNodes:[nodesDict objectForKey:name]];
				if ([name isEqualToString:@"enclosure"])
				{
					// enclosure is flattened as a separate dictionary for some reason
					NSDictionary *encDict = [(NSXMLElement *)node attributesAsDictionary];
					[dict setObject:encDict forKey:@"enclosure"];
					
				}
                else if ([name isEqualToString:@"pubDate"])
                {
					// pubDate is expected to be an NSDate by SUAppcastItem, but the RSS class was returning an NSString
					NSDate *date = [NSDate dateWithNaturalLanguageString:[node stringValue]];
					if (date)
						[dict setObject:date forKey:name];
				}
				else if ([name isEqualToString:@"sparkle:deltas"])
				{
					NSMutableArray *deltas = [NSMutableArray array];
					NSEnumerator *childEnum = [[node children] objectEnumerator];
					for (NSXMLNode *child in childEnum) {
						if ([[child name] isEqualToString:@"enclosure"])
							[deltas addObject:[(NSXMLElement *)child attributesAsDictionary]];
					}
					[dict setObject:deltas forKey:@"deltas"];
				}
				else if (name != nil)
				{
					// add all other values as strings
					NSString *theValue = [[node stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
					if (theValue != nil) {
						[dict setObject:theValue forKey:name];
					}
				}
            }
            
			NSString *errString;
			SUAppcastItem *anItem = [[[SUAppcastItem alloc] initWithDictionary:dict failureReason:&errString] autorelease];
            if (anItem)
            {
                [appcastItems addObject:anItem];
			}
            else
            {
				SULog(@"Sparkle Updater: Failed to parse appcast item: %@.\nAppcast dictionary was: %@", errString, dict);
            }
            [nodesDict removeAllObjects];
            [dict removeAllObjects];
		}
	}
	
	if ([appcastItems count])
    {
		NSSortDescriptor *sort = [[[NSSortDescriptor alloc] initWithKey:@"date" ascending:NO] autorelease];
		[appcastItems sortUsingDescriptors:[NSArray arrayWithObject:sort]];
		self.items = appcastItems;
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

- (void)download:(NSURLDownload *)aDownload didFailWithError:(NSError *)error
{
	if (downloadFilename)
	{
		[[NSFileManager defaultManager] removeItemAtPath:downloadFilename error:nil];
	}
	self.downloadFilename = nil;
    
	[self reportError:error];
}

- (NSURLRequest *)download:(NSURLDownload *)aDownload willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)redirectResponse
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

- (NSXMLNode *)bestNodeInNodes:(NSArray *)nodes
{
	// We use this method to pick out the localized version of a node when one's available.
    if ([nodes count] == 1)
        return [nodes objectAtIndex:0];
    else if ([nodes count] == 0)
        return nil;
    
    NSMutableArray *languages = [NSMutableArray array];
    NSString *lang;
    NSUInteger i;
	for (NSXMLElement *node in nodes) {
        lang = [[node attributeForName:@"xml:lang"] stringValue];
        [languages addObject:(lang ? lang : @"")];
    }
    lang = [[NSBundle preferredLocalizationsFromArray:languages] objectAtIndex:0];
    i = [languages indexOfObject:([languages containsObject:lang] ? lang : @"")];
    if (i == NSNotFound)
        i = 0;
    return [nodes objectAtIndex:i];
}

@end
