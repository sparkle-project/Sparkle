//
//  SUAppcastItem.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/12/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import "SUUpdater.h"

#import "SUAppcast.h"
#import "SUAppcastItem.h"
#import "SUVersionComparisonProtocol.h"
#import "SUAppcastItem.h"
#import "SULog.h"

@interface SUAppcastItem ()
@property (copy, readwrite) NSString *title;
@property (copy, readwrite) NSDate *date;
@property (copy, readwrite) NSString *itemDescription;
@property (retain, readwrite) NSURL *releaseNotesURL;
@property (copy, readwrite) NSString *DSASignature;
@property (copy, readwrite) NSString *minimumSystemVersion;
@property (copy, readwrite) NSString *maximumSystemVersion;
@property (retain, readwrite) NSURL *fileURL;
@property (copy, readwrite) NSString *versionString;
@property (copy, readwrite) NSString *displayVersionString;
@property (copy, readwrite) NSDictionary *deltaUpdates;
@property (retain, readwrite) NSURL *infoURL;
@end

@implementation SUAppcastItem
@synthesize date;
@synthesize deltaUpdates;
@synthesize displayVersionString;
@synthesize DSASignature;
@synthesize fileURL;
@synthesize infoURL;
@synthesize itemDescription;
@synthesize maximumSystemVersion;
@synthesize minimumSystemVersion;
@synthesize releaseNotesURL;
@synthesize title;
@synthesize versionString;

- (BOOL)isDeltaUpdate
{
	return [[propertiesDictionary objectForKey:@"enclosure"] objectForKey:@"sparkle:deltaFrom"] != nil;
}

- (BOOL)isCriticalUpdate
{
    return [[propertiesDictionary objectForKey:@"sparkle:tags"] containsObject:@"sparkle:criticalUpdate"];
}

- initWithDictionary:(NSDictionary *)dict
{
	return [self initWithDictionary:dict failureReason:nil];
}

- initWithDictionary:(NSDictionary *)dict failureReason:(NSString**)error
{
	self = [super init];
	if (self)
	{
		id enclosure = [dict objectForKey:@"enclosure"];
		
		// Try to find a version string.
		// Finding the new version number from the RSS feed is a little bit hacky. There are two ways:
		// 1. A "sparkle:version" attribute on the enclosure tag, an extension from the RSS spec.
		// 2. If there isn't a version attribute, Sparkle will parse the path in the enclosure, expecting
		//    that it will look like this: http://something.com/YourApp_0.5.zip. It'll read whatever's between the last
		//    underscore and the last period as the version number. So name your packages like this: APPNAME_VERSION.extension.
		//    The big caveat with this is that you can't have underscores in your version strings, as that'll confuse Sparkle.
		//    Feel free to change the separator string to a hyphen or something more suited to your needs if you like.
		NSString *newVersion = [enclosure objectForKey:@"sparkle:version"];
		if( newVersion == nil )
			newVersion = [dict objectForKey:@"sparkle:version"];	// UK 2007-08-31 Get version from the item, in case it's a download-less item (i.e. paid upgrade).
		if (newVersion == nil) // no sparkle:version attribute anywhere?
		{
			// Separate the url by underscores and take the last component, as that'll be closest to the end,
			// then we remove the extension. Hopefully, this will be the version.
			NSArray *fileComponents = [[enclosure objectForKey:@"url"] componentsSeparatedByString:@"_"];
			if ([fileComponents count] > 1)
				newVersion = [[fileComponents lastObject] stringByDeletingPathExtension];
		}
		
		if(!newVersion )
		{
			if (error)
				*error = @"Feed item lacks sparkle:version attribute, and version couldn't be deduced from file name (would have used last component of a file name like AppName_1.3.4.zip)";
			[self release];
			return nil;
		}
        
		propertiesDictionary = [[NSMutableDictionary alloc] initWithDictionary:dict];
		[self setTitle:[dict objectForKey:@"title"]];
		[self setDate:[dict objectForKey:@"pubDate"]];
		[self setItemDescription:[dict objectForKey:@"description"]];
		
		NSString*	theInfoURL = [dict objectForKey:@"link"];
		if( theInfoURL )
		{
			if( ![theInfoURL isKindOfClass: [NSString class]] )
				SULog(@"SUAppcastItem -initWithDictionary: Info URL is not of valid type.");
			else
				[self setInfoURL:[NSURL URLWithString:theInfoURL]];
		}
		
		// Need an info URL or an enclosure URL. Former to show "More Info"
		//	page, latter to download & install:
		if( !enclosure && !theInfoURL )
		{
			if (error)
				*error = @"No enclosure in feed item";
			[self release];
			return nil;
		}

		NSString*	enclosureURLString = [enclosure objectForKey:@"url"];
		if( !enclosureURLString && !theInfoURL )
		{
			if (error)
				*error = @"Feed item's enclosure lacks URL";
			[self release];
			return nil;
		}
		
		if( enclosureURLString )
			[self setFileURL: [NSURL URLWithString: [enclosureURLString stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]];
		if( enclosure )
			[self setDSASignature:[enclosure objectForKey:@"sparkle:dsaSignature"]];		
		
		[self setVersionString: newVersion];
		[self setMinimumSystemVersion: [dict objectForKey:@"sparkle:minimumSystemVersion"]];
        [self setMaximumSystemVersion: [dict objectForKey:@"sparkle:maximumSystemVersion"]];
		
		NSString *shortVersionString = [enclosure objectForKey:@"sparkle:shortVersionString"];
        if (nil == shortVersionString)
            shortVersionString = [dict objectForKey:@"sparkle:shortVersionString"]; // fall back on the <item>
        
		if (shortVersionString)
			[self setDisplayVersionString: shortVersionString];
		else
			[self setDisplayVersionString: [self versionString]];
		
		// Find the appropriate release notes URL.
		if ([dict objectForKey:@"sparkle:releaseNotesLink"])
			[self setReleaseNotesURL:[NSURL URLWithString:[dict objectForKey:@"sparkle:releaseNotesLink"]]];
		else if ([[self itemDescription] hasPrefix:@"http://"] || [[self itemDescription] hasPrefix:@"https://"]) // if the description starts with http:// or https:// use that.
			[self setReleaseNotesURL:[NSURL URLWithString:[self itemDescription]]];
		else
			[self setReleaseNotesURL:nil];

        if ([dict objectForKey:@"deltas"])
		{
            NSMutableDictionary *deltas = [NSMutableDictionary dictionary];
            NSArray *deltaDictionaries = [dict objectForKey:@"deltas"];
            NSEnumerator *deltaDictionariesEnum = [deltaDictionaries objectEnumerator];
            NSDictionary *deltaDictionary;
            while ((deltaDictionary = [deltaDictionariesEnum nextObject]))
			{
                NSMutableDictionary *fakeAppCastDict = [dict mutableCopy];
                [fakeAppCastDict removeObjectForKey:@"deltas"];
                [fakeAppCastDict setObject:deltaDictionary forKey:@"enclosure"];
                SUAppcastItem *deltaItem = [[[self class] alloc] initWithDictionary:fakeAppCastDict];
                [fakeAppCastDict release];

                [deltas setObject:deltaItem forKey:[deltaDictionary objectForKey:@"sparkle:deltaFrom"]];
                [deltaItem release];
            }
            [self setDeltaUpdates:deltas];
        }
	}
	return self;
}

- (void)dealloc
{
    [self setTitle:nil];
    [self setDate:nil];
    [self setItemDescription:nil];
    [self setReleaseNotesURL:nil];
    [self setDSASignature:nil];
	[self setMinimumSystemVersion: nil];
    [self setFileURL:nil];
    [self setVersionString:nil];
	[self setDisplayVersionString:nil];
	[self setInfoURL:nil];
	[propertiesDictionary release];
    [super dealloc];
}

- (NSDictionary *)propertiesDictionary
{
	return propertiesDictionary;
}

@end
