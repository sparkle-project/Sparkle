//
//  SUAppcastItem.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/12/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import "Sparkle.h"
#import "SUAppcastItem.h"

@implementation SUAppcastItem

// Attack of accessors!

- (NSString *)title { return [[title retain] autorelease]; }

- (void)setTitle:(NSString *)aTitle
{
    [title release];
    title = [aTitle copy];
}


- (NSDate *)date { return [[date retain] autorelease]; }

- (void)setDate:(NSDate *)aDate
{
    [date release];
    date = [aDate copy];
}


- (NSString *)description { return [[description retain] autorelease]; }

- (void)setDescription:(NSString *)aDescription
{
    [description release];
    description = [aDescription copy];
}


- (NSURL *)releaseNotesURL { return [[releaseNotesURL retain] autorelease]; }

- (void)setReleaseNotesURL:(NSURL *)aReleaseNotesURL
{
    [releaseNotesURL release];
    releaseNotesURL = [aReleaseNotesURL copy];
}


- (NSString *)DSASignature { return [[DSASignature retain] autorelease]; }

- (void)setDSASignature:(NSString *)aDSASignature
{
    [DSASignature release];
    DSASignature = [aDSASignature copy];
}
			

- (NSURL *)fileURL { return [[fileURL retain] autorelease]; }

- (void)setFileURL:(NSURL *)aFileURL
{
    [fileURL release];
    fileURL = [aFileURL copy];
}


- (NSString *)versionString { return [[versionString retain] autorelease]; }

- (void)setVersionString:(NSString *)s
{
    [versionString release];
    versionString = [s copy];
}


- (NSString *)displayVersionString { return [[displayVersionString retain] autorelease]; }

- (void)setDisplayVersionString:(NSString *)s
{
    [displayVersionString release];
    displayVersionString = [s copy];
}


- (NSString *)minimumSystemVersion { return [[minimumSystemVersion retain] autorelease]; }
- (void)setMinimumSystemVersion:(NSString *)systemVersionString
{
	[minimumSystemVersion release];
	minimumSystemVersion = [systemVersionString copy];
}

- initWithDictionary:(NSDictionary *)dict
{
	self = [super init];
	if (self)
	{
		propertiesDictionary = [dict retain];
		[self setTitle:[dict objectForKey:@"title"]];
		[self setDate:[dict objectForKey:@"pubDate"]];
		[self setDescription:[dict objectForKey:@"description"]];
		
		id enclosure = [dict objectForKey:@"enclosure"];
		if (enclosure == nil || [enclosure objectForKey:@"url"] == nil)
			[NSException raise:@"SUAppcastException" format:@"Couldn't find an download URL for feed entry %@!", [self title]];
		[self setFileURL:[NSURL URLWithString:[[enclosure objectForKey:@"url"] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]];
		[self setDSASignature:[enclosure objectForKey:@"sparkle:dsaSignature"]];		
		
		// Try to find a version string.
		// Finding the new version number from the RSS feed is a little bit hacky. There are two ways:
		// 1. A "sparkle:version" attribute on the enclosure tag, an extension from the RSS spec.
		// 2. If there isn't a version attribute, Sparkle will parse the path in the enclosure, expecting
		//    that it will look like this: http://something.com/YourApp_0.5.zip. It'll read whatever's between the last
		//    underscore and the last period as the version number. So name your packages like this: APPNAME_VERSION.extension.
		//    The big caveat with this is that you can't have underscores in your version strings, as that'll confuse Sparkle.
		//    Feel free to change the separator string to a hyphen or something more suited to your needs if you like.
		NSString *newVersion = [enclosure objectForKey:@"sparkle:version"];
		if (!newVersion) // no sparkle:version attribute
		{
			// Separate the url by underscores and take the last component, as that'll be closest to the end,
			// then we remove the extension. Hopefully, this will be the version.
			NSArray *fileComponents = [[enclosure objectForKey:@"url"] componentsSeparatedByString:@"_"];
			if ([fileComponents count] > 1)
				newVersion = [[fileComponents lastObject] stringByDeletingPathExtension];
			else
				[NSException raise:@"SUAppcastException" format:@"Couldn't find a version string for %@! You need a sparkle:version attribute.", [enclosure objectForKey:@"url"]];
		}
		[self setVersionString:newVersion];
		[self setMinimumSystemVersion:[dict objectForKey:@"sparkle:minimumSystemVersion"]];
		
		NSString *shortVersionString = [enclosure objectForKey:@"sparkle:shortVersionString"];
		if (shortVersionString)
			[self setDisplayVersionString:shortVersionString];
		else
			[self setDisplayVersionString:[self versionString]];
		
		// Find the appropriate release notes URL.
		if ([dict objectForKey:@"sparkle:releaseNotesLink"])
			[self setReleaseNotesURL:[NSURL URLWithString:[dict objectForKey:@"sparkle:releaseNotesLink"]]];
		else if ([[self description] hasPrefix:@"http://"]) // if the description starts with http://, use that.
			[self setReleaseNotesURL:[NSURL URLWithString:[self description]]];
		else
			[self setReleaseNotesURL:nil];
	}
	return self;
}

- (void)dealloc
{
    [self setTitle:nil];
    [self setDate:nil];
    [self setDescription:nil];
    [self setReleaseNotesURL:nil];
    [self setDSASignature:nil];
    [self setFileURL:nil];
    [self setVersionString:nil];
	[self setDisplayVersionString:nil];
	[propertiesDictionary release];
    [super dealloc];
}

- (NSDictionary *)propertiesDictionary
{
	return propertiesDictionary;
}

@end
