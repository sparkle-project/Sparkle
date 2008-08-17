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
	if (title == aTitle) return;
    [title release];
    title = [aTitle copy];
}


- (NSDate *)date { return [[date retain] autorelease]; }

- (void)setDate:(NSDate *)aDate
{
	if (date == aDate) return;
    [date release];
    date = [aDate copy];
}


- (NSString *)itemDescription { return [[itemDescription retain] autorelease]; }

- (void)setItemDescription:(NSString *)anItemDescription
{
	if (itemDescription == anItemDescription) return;
    [itemDescription release];
    itemDescription = [anItemDescription copy];
}


- (NSURL *)releaseNotesURL { return [[releaseNotesURL retain] autorelease]; }

- (void)setReleaseNotesURL:(NSURL *)aReleaseNotesURL
{
	if (releaseNotesURL == aReleaseNotesURL) return;
    [releaseNotesURL release];
    releaseNotesURL = [aReleaseNotesURL copy];
}


- (NSString *)DSASignature { return [[DSASignature retain] autorelease]; }

- (void)setDSASignature:(NSString *)aDSASignature
{
	if (DSASignature == aDSASignature) return;
    [DSASignature release];
    DSASignature = [aDSASignature copy];
}
			

- (NSURL *)fileURL { return [[fileURL retain] autorelease]; }

- (void)setFileURL:(NSURL *)aFileURL
{
	if (fileURL == aFileURL) return;
    [fileURL release];
    fileURL = [aFileURL copy];
}


- (NSString *)versionString { return [[versionString retain] autorelease]; }

- (void)setVersionString:(NSString *)s
{
	if (versionString == s) return;
    [versionString release];
    versionString = [s copy];
}


- (NSString *)displayVersionString { return [[displayVersionString retain] autorelease]; }

- (void)setDisplayVersionString:(NSString *)s
{
	if (displayVersionString == s) return;
    [displayVersionString release];
    displayVersionString = [s copy];
}


- (NSString *)minimumSystemVersion { return [[minimumSystemVersion retain] autorelease]; }
- (void)setMinimumSystemVersion:(NSString *)systemVersionString
{
	if (minimumSystemVersion == systemVersionString) return;
	[minimumSystemVersion release];
	minimumSystemVersion = [systemVersionString copy];
}

- initWithDictionary:(NSDictionary *)dict
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
		if (newVersion == nil) // no sparkle:version attribute
		{
			// Separate the url by underscores and take the last component, as that'll be closest to the end,
			// then we remove the extension. Hopefully, this will be the version.
			NSArray *fileComponents = [[enclosure objectForKey:@"url"] componentsSeparatedByString:@"_"];
			if ([fileComponents count] > 1)
				newVersion = [[fileComponents lastObject] stringByDeletingPathExtension];
		}
        
		if (enclosure == nil || [enclosure objectForKey:@"url"] == nil || newVersion == nil)
        {
            [self release];
            self = nil;
        }
        else
        {
            propertiesDictionary = [[NSMutableDictionary alloc] initWithDictionary:dict];
            [self setTitle:[dict objectForKey:@"title"]];
            [self setDate:[dict objectForKey:@"pubDate"]];
            [self setItemDescription:[dict objectForKey:@"description"]];
            
            [self setFileURL:[NSURL URLWithString:[[enclosure objectForKey:@"url"] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]];
            [self setDSASignature:[enclosure objectForKey:@"sparkle:dsaSignature"]];		
            
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
            else if ([[self itemDescription] hasPrefix:@"http://"]) // if the description starts with http://, use that.
                [self setReleaseNotesURL:[NSURL URLWithString:[self itemDescription]]];
            else
                [self setReleaseNotesURL:nil];
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
