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
@property (readonly, copy) NSDictionary *attributesAsDictionary;
@end

@implementation NSXMLElement (SUAppcastExtensions)
- (NSDictionary *)attributesAsDictionary
{
    NSEnumerator *attributeEnum = [[self attributes] objectEnumerator];
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];

    for (NSXMLNode *attribute in attributeEnum) {
        dictionary[[attribute name]] = [attribute stringValue];
    }
    return dictionary;
}
@end

@interface SUAppcast () <NSURLDownloadDelegate>
@property (copy) NSString *downloadFilename;
@property (strong) NSURLDownload *download;
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

- (void)fetchAppcastFromURL:(NSURL *)url
{
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:30.0];
    if (self.userAgentString) {
        [request setValue:self.userAgentString forHTTPHeaderField:@"User-Agent"];
    }

    [request setValue:@"application/rss+xml,*/*;q=0.1" forHTTPHeaderField:@"Accept"];

    self.download = [[NSURLDownload alloc] initWithRequest:request delegate:self];
}

- (void)download:(NSURLDownload *)__unused aDownload decideDestinationWithSuggestedFilename:(NSString *)filename
{
    NSString *destinationFilename = NSTemporaryDirectory();
	if (destinationFilename)
	{
        destinationFilename = [destinationFilename stringByAppendingPathComponent:filename];
        [self.download setDestination:destinationFilename allowOverwrite:NO];
    }
}

- (void)download:(NSURLDownload *)__unused aDownload didCreateDestination:(NSString *)path
{
    self.downloadFilename = path;
}

- (void)downloadDidFinish:(NSURLDownload *)__unused aDownload
{
    NSError *error = nil;

    NSXMLDocument *document = nil;
    BOOL failed = NO;
    NSArray *xmlItems = nil;
    NSMutableArray *appcastItems = [NSMutableArray array];

	if (self.downloadFilename)
	{
        NSUInteger options = 0;
        options = NSXMLNodeLoadExternalEntitiesSameOriginOnly;
        document = [[NSXMLDocument alloc] initWithContentsOfURL:[NSURL fileURLWithPath:self.downloadFilename] options:options error:&error];

        [[NSFileManager defaultManager] removeItemAtPath:self.downloadFilename error:nil];
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
                        NSMutableArray *nodes = nodesDict[name];
                        if (nodes == nil)
                        {
                            nodes = [NSMutableArray array];
                            nodesDict[name] = nodes;
                        }
                        [nodes addObject:node];
                    }
                    node = [node nextSibling];
                }
            }

            for (NSString *name in nodesDict)
            {
                node = [self bestNodeInNodes:nodesDict[name]];
				if ([name isEqualToString:@"enclosure"])
				{
                    // enclosure is flattened as a separate dictionary for some reason
                    NSDictionary *encDict = [(NSXMLElement *)node attributesAsDictionary];
                    dict[@"enclosure"] = encDict;

				}
                else if ([name isEqualToString:@"pubDate"])
                {
                    // pubDate is expected to be an NSDate by SUAppcastItem, but the RSS class was returning an NSString
                    NSDate *date = [NSDate dateWithNaturalLanguageString:[node stringValue]];
                    if (date)
                        dict[name] = date;
				}
				else if ([name isEqualToString:@"sparkle:deltas"])
				{
                    NSMutableArray *deltas = [NSMutableArray array];
                    NSEnumerator *childEnum = [[node children] objectEnumerator];
                    for (NSXMLNode *child in childEnum) {
                        if ([[child name] isEqualToString:@"enclosure"])
                            [deltas addObject:[(NSXMLElement *)child attributesAsDictionary]];
                    }
                    dict[@"deltas"] = deltas;
				}
				else if (name != nil)
				{
                    // add all other values as strings
                    NSString *theValue = [[node stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    if (theValue != nil) {
                        dict[name] = theValue;
                    }
                }
            }

            NSString *errString;
            SUAppcastItem *anItem = [[SUAppcastItem alloc] initWithDictionary:dict failureReason:&errString];
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
        NSSortDescriptor *sort = [[NSSortDescriptor alloc] initWithKey:@"date" ascending:NO];
        [appcastItems sortUsingDescriptors:@[sort]];
        self.items = appcastItems;
    }

	if (failed)
    {
        [self reportError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUAppcastParseError userInfo:@{ NSLocalizedDescriptionKey: SULocalizedString(@"An error occurred while parsing the update feed.", nil) }]];
	}
    else if ([self.delegate respondsToSelector:@selector(appcastDidFinishLoading:)])
    {
        [self.delegate appcastDidFinishLoading:self];
    }
}

- (void)download:(NSURLDownload *)__unused aDownload didFailWithError:(NSError *)error
{
	if (self.downloadFilename)
	{
        [[NSFileManager defaultManager] removeItemAtPath:self.downloadFilename error:nil];
    }
    self.downloadFilename = nil;

    [self reportError:error];
}

- (NSURLRequest *)download:(NSURLDownload *)__unused aDownload willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)__unused redirectResponse
{
    return request;
}

- (void)reportError:(NSError *)error
{
	if ([self.delegate respondsToSelector:@selector(appcast:failedToLoadWithError:)])
	{
		[self.delegate appcast:self failedToLoadWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUAppcastError userInfo:@{NSLocalizedDescriptionKey: SULocalizedString(@"An error occurred in retrieving update information. Please try again later.", nil), NSLocalizedFailureReasonErrorKey: [error localizedDescription]}]];
    }
}

- (NSXMLNode *)bestNodeInNodes:(NSArray *)nodes
{
    // We use this method to pick out the localized version of a node when one's available.
    if ([nodes count] == 1)
        return nodes[0];
    else if ([nodes count] == 0)
        return nil;

    NSMutableArray *languages = [NSMutableArray array];
    NSString *lang;
    NSUInteger i;
    for (NSXMLElement *node in nodes) {
        lang = [[node attributeForName:@"xml:lang"] stringValue];
        [languages addObject:(lang ? lang : @"")];
    }
    lang = [NSBundle preferredLocalizationsFromArray:languages][0];
    i = [languages indexOfObject:([languages containsObject:lang] ? lang : @"")];
    if (i == NSNotFound) {
        i = 0;
    }
    return nodes[i];
}

@end
