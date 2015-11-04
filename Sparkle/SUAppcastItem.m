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
@property (strong, readwrite) NSURL *releaseNotesURL;
@property (copy, readwrite) NSString *DSASignature;
@property (copy, readwrite) NSString *minimumSystemVersion;
@property (copy, readwrite) NSString *maximumSystemVersion;
@property (strong, readwrite) NSURL *fileURL;
@property (copy, readwrite) NSString *versionString;
@property (copy, readwrite) NSString *displayVersionString;
@property (copy, readwrite) NSDictionary *deltaUpdates;
@property (strong, readwrite) NSURL *infoURL;
@property (readwrite, copy) NSDictionary *propertiesDictionary;
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
@synthesize propertiesDictionary;

- (BOOL)isDeltaUpdate
{
    return self.propertiesDictionary[SURSSElementEnclosure][SUAppcastAttributeDeltaFrom] != nil;
}

- (BOOL)isCriticalUpdate
{
    return [self.propertiesDictionary[SUAppcastElementTags] containsObject:SUAppcastElementCriticalUpdate];
}

- (BOOL)isInformationOnlyUpdate
{
    return self.infoURL && !self.fileURL;
}

- (instancetype)initWithDictionary:(NSDictionary *)dict
{
    return [self initWithDictionary:dict failureReason:nil];
}

- (instancetype)initWithDictionary:(NSDictionary *)dict failureReason:(NSString *__autoreleasing *)error
{
    self = [super init];
    if (self) {
        id enclosure = dict[SURSSElementEnclosure];

        // Try to find a version string.
        // Finding the new version number from the RSS feed is a little bit hacky. There are two ways:
        // 1. A "sparkle:version" attribute on the enclosure tag, an extension from the RSS spec.
        // 2. If there isn't a version attribute, Sparkle will parse the path in the enclosure, expecting
        //    that it will look like this: http://something.com/YourApp_0.5.zip. It'll read whatever's between the last
        //    underscore and the last period as the version number. So name your packages like this: APPNAME_VERSION.extension.
        //    The big caveat with this is that you can't have underscores in your version strings, as that'll confuse Sparkle.
        //    Feel free to change the separator string to a hyphen or something more suited to your needs if you like.
        NSString *newVersion = enclosure[SUAppcastAttributeVersion];
        if (newVersion == nil) {
            newVersion = dict[SUAppcastAttributeVersion]; // Get version from the item, in case it's a download-less item (i.e. paid upgrade).
        }
        if (newVersion == nil) // no sparkle:version attribute anywhere?
        {
            SULog(@"warning: <%@> for URL '%@' is missing %@ attribute. Version comparison may be unreliable. Please always specify %@", SURSSElementEnclosure, enclosure[SURSSAttributeURL], SUAppcastAttributeVersion, SUAppcastAttributeVersion);

            // Separate the url by underscores and take the last component, as that'll be closest to the end,
            // then we remove the extension. Hopefully, this will be the version.
            NSArray *fileComponents = [enclosure[SURSSAttributeURL] componentsSeparatedByString:@"_"];
            if ([fileComponents count] > 1) {
                newVersion = [[fileComponents lastObject] stringByDeletingPathExtension];
            }
        }

        if (!newVersion) {
            if (error) {
                *error = [NSString stringWithFormat:@"Feed item lacks %@ attribute, and version couldn't be deduced from file name (would have used last component of a file name like AppName_1.3.4.zip)", SUAppcastAttributeVersion];
            }
            return nil;
        }

        propertiesDictionary = [[NSMutableDictionary alloc] initWithDictionary:dict];
        self.title = dict[SURSSElementTitle];
        self.date = dict[SURSSElementPubDate];
        self.itemDescription = dict[SURSSElementDescription];

        NSString *theInfoURL = dict[SURSSElementLink];
        if (theInfoURL) {
            if (![theInfoURL isKindOfClass:[NSString class]]) {
                SULog(@"%@ -%@ Info URL is not of valid type.", NSStringFromClass([self class]), NSStringFromSelector(_cmd));
            } else {
                self.infoURL = [NSURL URLWithString:theInfoURL];
            }
        }

        // Need an info URL or an enclosure URL. Former to show "More Info"
        //	page, latter to download & install:
        if (!enclosure && !theInfoURL) {
            if (error) {
                *error = @"No enclosure in feed item";
            }
            return nil;
        }

        NSString *enclosureURLString = enclosure[SURSSAttributeURL];
        if (!enclosureURLString && !theInfoURL) {
            if (error) {
                *error = @"Feed item's enclosure lacks URL";
            }
            return nil;
        }

        if (enclosureURLString) {
            NSString *fileURLString = [[enclosureURLString stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
            self.fileURL = [NSURL URLWithString:fileURLString];
        }
        if (enclosure) {
            self.DSASignature = enclosure[SUAppcastAttributeDSASignature];
        }

        self.versionString = newVersion;
        self.minimumSystemVersion = dict[SUAppcastElementMinimumSystemVersion];
        self.maximumSystemVersion = dict[SUAppcastElementMaximumSystemVersion];

        NSString *shortVersionString = enclosure[SUAppcastAttributeShortVersionString];
        if (nil == shortVersionString) {
            shortVersionString = dict[SUAppcastAttributeShortVersionString]; // fall back on the <item>
        }

        if (shortVersionString) {
            self.displayVersionString = shortVersionString;
        } else {
            self.displayVersionString = self.versionString;
        }

        // Find the appropriate release notes URL.
        NSString *releaseNotesString = dict[SUAppcastElementReleaseNotesLink];
        if (releaseNotesString) {
            self.releaseNotesURL = [NSURL URLWithString:releaseNotesString];
        } else if ([self.itemDescription hasPrefix:@"http://"] || [self.itemDescription hasPrefix:@"https://"]) { // if the description starts with http:// or https:// use that.
            self.releaseNotesURL = [NSURL URLWithString:self.itemDescription];
        } else {
            self.releaseNotesURL = nil;
        }

        NSArray *deltaDictionaries = dict[SUAppcastElementDeltas];
        if (deltaDictionaries) {
            NSMutableDictionary *deltas = [NSMutableDictionary dictionary];
            for (NSDictionary *deltaDictionary in deltaDictionaries) {
                NSString *deltaFrom = deltaDictionary[SUAppcastAttributeDeltaFrom];
                if (!deltaFrom) continue;

                NSMutableDictionary *fakeAppCastDict = [dict mutableCopy];
                [fakeAppCastDict removeObjectForKey:SUAppcastElementDeltas];
                fakeAppCastDict[SURSSElementEnclosure] = deltaDictionary;
                SUAppcastItem *deltaItem = [[SUAppcastItem alloc] initWithDictionary:fakeAppCastDict];

                deltas[deltaFrom] = deltaItem;
            }
            self.deltaUpdates = deltas;
        }
    }
    return self;
}

@end
