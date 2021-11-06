//
//  SUAppcastItem.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/12/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import "SUAppcastItem.h"
#import "SUVersionComparisonProtocol.h"
#import "SULog.h"
#import "SUConstants.h"
#import "SUSignatures.h"
#import "SPUInstallationType.h"
#import "SPUAppcastItemState.h"
#import "SPUAppcastItemStateResolver.h"
#import "SPUAppcastItemStateResolver+Private.h"


#include "AppKitPrevention.h"

static NSString *SUAppcastItemDeltaUpdatesKey = @"deltaUpdates";
static NSString *SUAppcastItemDisplayVersionStringKey = @"displayVersionString";
static NSString *SUAppcastItemSignaturesKey = @"signatures";
static NSString *SUAppcastItemFileURLKey = @"fileURL";
static NSString *SUAppcastItemInfoURLKey = @"infoURL";
static NSString *SUAppcastItemContentLengthKey = @"contentLength";
static NSString *SUAppcastItemDescriptionKey = @"itemDescription";
static NSString *SUAppcastItemMaximumSystemVersionKey = @"maximumSystemVersion";
static NSString *SUAppcastItemMinimumSystemVersionKey = @"minimumSystemVersion";
static NSString *SUAppcastItemReleaseNotesURLKey = @"releaseNotesURL";
static NSString *SUAppcastItemFullReleaseNotesURLKey = @"fullReleaseNotesURL";
static NSString *SUAppcastItemTitleKey = @"title";
static NSString *SUAppcastItemVersionStringKey = @"versionString";
static NSString *SUAppcastItemPropertiesKey = @"propertiesDictionary";
static NSString *SUAppcastItemInstallationTypeKey = @"SUAppcastItemInstallationType";
static NSString *SUAppcastItemStateKey = @"SUAppcastItemState";

@interface SUAppcastItem ()

@property (readonly, nullable) SUSignatures *signatures;

// Auxillary appcast item state that needs to be evaluated based on the host state
// This may be nil if the client creates an SUAppcastItem with a deprecated initializer
// In that case we will need to fallback to safe behavior
@property (nonatomic, readonly, nullable) SPUAppcastItemState *state;

// Indicates if we have any critical information. Used as a fallback if state is nil
@property (nonatomic, readonly) BOOL hasCriticalInformation;

// Indicates the versions we update from that are informational-only
@property (nonatomic, readonly, nullable) NSSet<NSString *> *informationalUpdateVersions;

@end

@implementation SUAppcastItem

@synthesize dateString = _dateString;
@synthesize deltaUpdates = _deltaUpdates;
@synthesize displayVersionString = _displayVersionString;
@synthesize signatures = _signatures;
@synthesize fileURL = _fileURL;
@synthesize contentLength = _contentLength;
@synthesize infoURL = _infoURL;
@synthesize itemDescription = _itemDescription;
@synthesize maximumSystemVersion = _maximumSystemVersion;
@synthesize minimumSystemVersion = _minimumSystemVersion;
@synthesize releaseNotesURL = _releaseNotesURL;
@synthesize fullReleaseNotesURL = _fullReleaseNotesURL;
@synthesize title = _title;
@synthesize versionString = _versionString;
@synthesize osString = _osString;
@synthesize propertiesDictionary = _propertiesDictionary;
@synthesize installationType = _installationType;
@synthesize minimumAutoupdateVersion = _minimumAutoupdateVersion;
@synthesize phasedRolloutInterval = _phasedRolloutInterval;
@synthesize state = _state;
@synthesize hasCriticalInformation = _hasCriticalInformation;
@synthesize informationalUpdateVersions = _informationalUpdateVersions;
@synthesize channel = _channel;

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)decoder
{
    self = [super init];
    
    if (self != nil) {
        _deltaUpdates = [decoder decodeObjectOfClasses:[NSSet setWithArray:@[[NSDictionary class], [SUAppcastItem class]]] forKey:SUAppcastItemDeltaUpdatesKey];
        _displayVersionString = [(NSString *)[decoder decodeObjectOfClass:[NSString class] forKey:SUAppcastItemDisplayVersionStringKey] copy];
        _signatures = (SUSignatures *)[decoder decodeObjectOfClass:[SUSignatures class] forKey:SUAppcastItemSignaturesKey];
        _fileURL = [decoder decodeObjectOfClass:[NSURL class] forKey:SUAppcastItemFileURLKey];
        _infoURL = [decoder decodeObjectOfClass:[NSURL class] forKey:SUAppcastItemInfoURLKey];
        
        if (_fileURL == nil && _infoURL == nil) {
            return nil;
        }
        
        _contentLength = (uint64_t)[decoder decodeInt64ForKey:SUAppcastItemContentLengthKey];
        
        NSString *installationType = [decoder decodeObjectOfClass:[NSString class] forKey:SUAppcastItemInstallationTypeKey];
        if (!SPUValidInstallationType(installationType)) {
            return nil;
        }
        
        SPUAppcastItemState *state = [decoder decodeObjectOfClass:[SPUAppcastItemState class] forKey:SUAppcastItemStateKey];
        _state = state;
        
        _installationType = [installationType copy];
        
        _itemDescription = [(NSString *)[decoder decodeObjectOfClass:[NSString class] forKey:SUAppcastItemDescriptionKey] copy];
        _maximumSystemVersion = [(NSString *)[decoder decodeObjectOfClass:[NSString class] forKey:SUAppcastItemMaximumSystemVersionKey] copy];
        _minimumSystemVersion = [(NSString *)[decoder decodeObjectOfClass:[NSString class] forKey:SUAppcastItemMinimumSystemVersionKey] copy];
        _minimumAutoupdateVersion = [(NSString *)[decoder decodeObjectOfClass:[NSString class] forKey:SUAppcastElementMinimumAutoupdateVersion] copy];
        _releaseNotesURL = [decoder decodeObjectOfClass:[NSURL class] forKey:SUAppcastItemReleaseNotesURLKey];
        _fullReleaseNotesURL = [decoder decodeObjectOfClass:[NSURL class] forKey:SUAppcastItemFullReleaseNotesURLKey];
        _title = [(NSString *)[decoder decodeObjectOfClass:[NSString class] forKey:SUAppcastItemTitleKey] copy];
        
        NSString *versionString =  [(NSString *)[decoder decodeObjectOfClass:[NSString class] forKey:SUAppcastItemVersionStringKey] copy];
        if (versionString == nil) {
            return nil;
        }
        
        _versionString = versionString;
        
        _osString = [(NSString *)[decoder decodeObjectOfClass:[NSString class] forKey:SUAppcastAttributeOsType] copy];
        
        NSDictionary *propertiesDictionary = [decoder decodeObjectOfClasses:[NSSet setWithArray:@[[NSDictionary class], [NSString class], [NSDate class], [NSArray class]]] forKey:SUAppcastItemPropertiesKey];
        if (propertiesDictionary == nil) {
            return nil;
        }
        
        _propertiesDictionary = propertiesDictionary;
        
        _phasedRolloutInterval = [decoder decodeObjectOfClass:[NSNumber class] forKey:SUAppcastElementPhasedRolloutInterval];
        
        _channel = [(NSString *)[decoder decodeObjectOfClass:[NSString class] forKey:SUAppcastElementChannel] copy];
    }
    
    return self;
}

- (void)encodeWithCoder:(NSCoder *)encoder
{
    if (self.deltaUpdates != nil) {
        [encoder encodeObject:self.deltaUpdates forKey:SUAppcastItemDeltaUpdatesKey];
    }
    
    if (self.displayVersionString != nil) {
        [encoder encodeObject:self.displayVersionString forKey:SUAppcastItemDisplayVersionStringKey];
    }
    
    if (self.signatures != nil) {
        [encoder encodeObject:self.signatures forKey:SUAppcastItemSignaturesKey];
    }
    
    if (self.fileURL != nil) {
        [encoder encodeObject:self.fileURL forKey:SUAppcastItemFileURLKey];
    }
    
    if (self.infoURL != nil) {
        [encoder encodeObject:self.infoURL forKey:SUAppcastItemInfoURLKey];
    }
    
    [encoder encodeInt64:(int64_t)self.contentLength forKey:SUAppcastItemContentLengthKey];
    
    if (self.itemDescription != nil) {
        [encoder encodeObject:self.itemDescription forKey:SUAppcastItemDescriptionKey];
    }
    
    if (self.maximumSystemVersion != nil) {
        [encoder encodeObject:self.maximumSystemVersion forKey:SUAppcastItemMaximumSystemVersionKey];
    }
    
    if (self.minimumSystemVersion != nil) {
        [encoder encodeObject:self.minimumSystemVersion forKey:SUAppcastItemMinimumSystemVersionKey];
    }
    
    if (self.minimumAutoupdateVersion != nil) {
        [encoder encodeObject:self.minimumAutoupdateVersion forKey:SUAppcastElementMinimumAutoupdateVersion];
    }
    
    if (self.state != nil) {
        [encoder encodeObject:self.state forKey:SUAppcastItemStateKey];
    }
    
    if (self.releaseNotesURL != nil) {
        [encoder encodeObject:self.releaseNotesURL forKey:SUAppcastItemReleaseNotesURLKey];
    }
    
    if (self.fullReleaseNotesURL != nil) {
        [encoder encodeObject:self.fullReleaseNotesURL forKey:SUAppcastItemFullReleaseNotesURLKey];
    }
    
    if (self.title != nil) {
        [encoder encodeObject:self.title forKey:SUAppcastItemTitleKey];
    }
    
    if (self.versionString != nil) {
        [encoder encodeObject:self.versionString forKey:SUAppcastItemVersionStringKey];
    }
    
    if (self.osString != nil) {
        [encoder encodeObject:self.osString forKey:SUAppcastAttributeOsType];
    }
    
    if (self.propertiesDictionary != nil) {
        [encoder encodeObject:self.propertiesDictionary forKey:SUAppcastItemPropertiesKey];
    }
    
    if (self.installationType != nil) {
        [encoder encodeObject:self.installationType forKey:SUAppcastItemInstallationTypeKey];
    }
    
    if (self.phasedRolloutInterval != nil) {
        [encoder encodeObject:self.phasedRolloutInterval forKey:SUAppcastElementPhasedRolloutInterval];
    }
    
    if (self.channel != nil) {
        [encoder encodeObject:self.channel forKey:SUAppcastElementChannel];
    }
}

- (BOOL)isDeltaUpdate
{
    NSDictionary *rssElementEnclosure = [self.propertiesDictionary objectForKey:SURSSElementEnclosure];
    return [rssElementEnclosure objectForKey:SUAppcastAttributeDeltaFrom] != nil;
}

- (BOOL)isCriticalUpdate
{
    if (self.state != nil) {
        return self.state.criticalUpdate;
    } else {
        return self.hasCriticalInformation;
    }
}

- (BOOL)isMajorUpgrade
{
    if (self.state != nil) {
        return self.state.majorUpgrade;
    } else {
        return NO;
    }
}

- (BOOL)minimumOperatingSystemVersionIsOK
{
    if (self.state != nil) {
        return self.state.minimumOperatingSystemVersionIsOK;
    } else {
        return YES;
    }
}

- (BOOL)maximumOperatingSystemVersionIsOK
{
    if (self.state != nil) {
        return self.state.maximumOperatingSystemVersionIsOK;
    } else {
        return YES;
    }
}

- (BOOL)isMacOsUpdate
{
    return self.osString == nil || [self.osString isEqualToString:SUAppcastAttributeValueMacOS];
}

- (NSDate *)date
{
    NSString *dateString = self.dateString;
    if (dateString == nil) {
        return nil;
    }
    
    NSDateFormatter* dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
    dateFormatter.dateFormat = @"E, dd MMM yyyy HH:mm:ss Z";
    
    return [dateFormatter dateFromString:dateString];
}

- (BOOL)isInformationOnlyUpdate
{
    if (self.state != nil) {
        return self.state.informationalUpdate;
    } else {
        return (self.informationalUpdateVersions != nil && self.informationalUpdateVersions.count == 0);
    }
}

+ (instancetype)emptyAppcastItem
{
    static SUAppcastItem *emptyAppcastItem;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        emptyAppcastItem = [[SUAppcastItem alloc] init];
    });
    return emptyAppcastItem;
}

// Initializer used for making delta items
- (nullable instancetype)initWithDictionary:(NSDictionary *)dict relativeToURL:(NSURL * _Nullable)appcastURL state:(SPUAppcastItemState * _Nullable)state
{
    return [self initWithDictionary:dict relativeToURL:nil stateResolver:nil resolvedState:state failureReason:nil];
}

// Exported public initializer
- (nullable instancetype)initWithDictionary:(NSDictionary *)dict relativeToURL:(NSURL * _Nullable)appcastURL stateResolver:(SPUAppcastItemStateResolver *)stateResolver failureReason:(NSString *__autoreleasing *)error
{
    return [self initWithDictionary:dict relativeToURL:appcastURL stateResolver:stateResolver resolvedState:nil failureReason:error];
}

// Deprecated
- (nullable instancetype)initWithDictionary:(NSDictionary *)dict
{
    return [self initWithDictionary:dict relativeToURL:nil stateResolver:nil resolvedState:nil failureReason:nil];
}

// Deprecated
- (nullable instancetype)initWithDictionary:(NSDictionary *)dict failureReason:(NSString *__autoreleasing *)error
{
    return [self initWithDictionary:dict relativeToURL:nil stateResolver:nil resolvedState:nil failureReason:error];
}

// Deprecated
- (nullable instancetype)initWithDictionary:(NSDictionary *)dict relativeToURL:(NSURL * _Nullable)appcastURL failureReason:(NSString *__autoreleasing *)error
{
    return [self initWithDictionary:dict relativeToURL:appcastURL stateResolver:nil resolvedState:nil failureReason:error];
}

- (nullable instancetype)initWithDictionary:(NSDictionary *)dict relativeToURL:(NSURL * _Nullable)appcastURL stateResolver:(SPUAppcastItemStateResolver * _Nullable)stateResolver resolvedState:(SPUAppcastItemState * _Nullable)resolvedState failureReason:(NSString *__autoreleasing *)error
{
    self = [super init];
    if (self) {
        _title = [(NSString *)[dict objectForKey:SURSSElementTitle] copy];
        
        NSDictionary *enclosure = [dict objectForKey:SURSSElementEnclosure];

        // Try to find a version string.
        // Finding the new version number from the RSS feed is a little bit hacky. There are a few ways:
        // 1. A "sparkle:version" attribute on the enclosure tag, an extension from the RSS spec.
        // 2. If there isn't a version attribute, see if there is a version element (this is now the recommended path).
        // 3. If there isn't a version element, Sparkle will parse the path in the enclosure, expecting
        //    that it will look like this: http://something.com/YourApp_0.5.zip. It'll read whatever's between the last
        //    underscore and the last period as the version number. So name your packages like this: APPNAME_VERSION.extension.
        //    The big caveat with this is that you can't have underscores in your version strings, as that'll confuse Sparkle.
        //    Feel free to change the separator string to a hyphen or something more suited to your needs if you like.
        NSString *newVersion = [enclosure objectForKey:SUAppcastAttributeVersion];
        if (newVersion == nil) {
            // Get version from the item
            newVersion = [dict objectForKey:SUAppcastElementVersion];
        }
        if (newVersion == nil)
        {
            // No sparkle:version element/attribute anywhere?
            SULog(SULogLevelError, @"warning: Item '%@' is missing '<%@>' element. Version comparison may be unreliable. Please always specify %@", _title, SUAppcastElementVersion, SUAppcastElementVersion);

            // Separate the url by underscores and take the last component, as that'll be closest to the end,
            // then we remove the extension. Hopefully, this will be the version.
            NSArray<NSString *> *fileComponents = [(NSString *)[enclosure objectForKey:SURSSAttributeURL] componentsSeparatedByString:@"_"];
            if ([fileComponents count] > 1) {
                newVersion = [[fileComponents lastObject] stringByDeletingPathExtension];
            }
        }

        if (!newVersion) {
            if (error) {
                *error = [NSString stringWithFormat:@"Feed item lacks %@ element, and version couldn't be deduced from file name (would have used last component of a file name like AppName_1.3.4.zip)", SUAppcastElementVersion];
            }
            return nil;
        }

        _propertiesDictionary = [[NSDictionary alloc] initWithDictionary:dict];
        _dateString = [(NSString *)[dict objectForKey:SURSSElementPubDate] copy];
        _itemDescription = [(NSString *)[dict objectForKey:SURSSElementDescription] copy];

        NSString *theInfoURL = [dict objectForKey:SURSSElementLink];
        if (theInfoURL) {
            if (![theInfoURL isKindOfClass:[NSString class]]) {
                SULog(SULogLevelError, @"%@ -%@ Info URL is not of valid type.", NSStringFromClass([self class]), NSStringFromSelector(_cmd));
            } else {
                NSURL *infoURL;
                if (appcastURL != nil) {
                    infoURL = [NSURL URLWithString:theInfoURL relativeToURL:appcastURL];
                } else {
                    infoURL = [NSURL URLWithString:theInfoURL];
                }
                
                if ([infoURL.scheme caseInsensitiveCompare:@"http"] == NSOrderedSame || [infoURL.scheme caseInsensitiveCompare:@"https"] == NSOrderedSame) {
                    _infoURL = infoURL;
                } else {
                    SULog(SULogLevelError, @"%@ -%@ Info URL must have a http or https URL scheme.", NSStringFromClass([self class]), NSStringFromSelector(_cmd));
                }
            }
        }

        // Need an info URL or an enclosure URL. Former to show "More Info"
        //	page, latter to download & install:
        if (!enclosure && !_infoURL) {
            if (error) {
                *error = @"No enclosure in feed item";
            }
            return nil;
        }
        
        if (_infoURL != nil) {
            // If enclosure doesn't exist, the update must be an informational update
            // Otherwise check presence of informational update element
            _informationalUpdateVersions = (enclosure != nil) ? [dict objectForKey:SUAppcastElementInformationalUpdate] : [NSSet set];
        } else {
            // Not an informational update
            _informationalUpdateVersions = nil;
        }

        NSString *enclosureURLString = [enclosure objectForKey:SURSSAttributeURL];
        if (!enclosureURLString && !_infoURL) {
            if (error) {
                *error = @"Feed item's enclosure lacks URL";
            }
            return nil;
        }
        
        if (enclosureURLString) {
            NSString *enclosureLengthString = [enclosure objectForKey:SURSSAttributeLength];
            long long contentLength = 0;
            if (enclosureLengthString != nil) {
                contentLength = [enclosureLengthString longLongValue];
            }
            _contentLength = (contentLength > 0) ? (uint64_t)contentLength : 0;
        }

        if (enclosureURLString) {
            // Sparkle used to always URL-encode, so for backwards compatibility spaces in URLs must be forgiven.
            NSString *fileURLString = [enclosureURLString stringByReplacingOccurrencesOfString:@" " withString:@"%20"];
            
            NSURL *fileURL;
            if (appcastURL != nil) {
                fileURL = [NSURL URLWithString:fileURLString relativeToURL:appcastURL];
            } else {
                fileURL = [NSURL URLWithString:fileURLString];
            }
            
            if ([fileURL.scheme caseInsensitiveCompare:@"http"] == NSOrderedSame || [fileURL.scheme caseInsensitiveCompare:@"https"] == NSOrderedSame) {
                _fileURL = fileURL;
            } else {
                SULog(SULogLevelError, @"File URLs must have a http or https URL scheme.");
                _fileURL = nil;
            }
        }
        if (enclosure) {
            _signatures = [[SUSignatures alloc] initWithDsa:[enclosure objectForKey:SUAppcastAttributeDSASignature] ed:[enclosure objectForKey:SUAppcastAttributeEDSignature]];
            _osString = [enclosure objectForKey:SUAppcastAttributeOsType];
        }

        _versionString = [(NSString *)newVersion copy];
        _minimumSystemVersion = [(NSString *)[dict objectForKey:SUAppcastElementMinimumSystemVersion] copy];
        _maximumSystemVersion = [(NSString *)[dict objectForKey:SUAppcastElementMaximumSystemVersion] copy];
        _minimumAutoupdateVersion = [(NSString *)[dict objectForKey:SUAppcastElementMinimumAutoupdateVersion] copy];
        
        NSString *channel = [dict objectForKey:SUAppcastElementChannel];
        if (channel != nil) {
            if (channel.length == 0) {
                SULog(SULogLevelError, @"warning: Item with version '%@' has zero-length channel; this will be ignored.", newVersion);
                _channel = nil;
            } else {
                // Reject characters in the channel name that may cause parsing problems in tools later
                NSMutableCharacterSet *allowedCharacterSet = [NSMutableCharacterSet alphanumericCharacterSet];
                [allowedCharacterSet addCharactersInString:@"_.-"];
                if ([channel rangeOfCharacterFromSet:allowedCharacterSet.invertedSet].location != NSNotFound) {
                    SULog(SULogLevelError, @"warning: Item with version '%@' has channel with invalid name. This channel will be ignored. Only [a-zA-Z0-9._-] is allowed.", newVersion);
                    _channel = nil;
                } else {
                    _channel = [channel copy];
                }
            }
        }
        
        // Grab critical update information
        NSDictionary * _Nullable criticalUpdateDictionaryFromAppcast = (NSDictionary *)[dict objectForKey:SUAppcastElementCriticalUpdate];
        NSArray *tags = [dict objectForKey:SUAppcastElementTags];
        
        NSDictionary * _Nullable criticalUpdateDictionary;
        if (criticalUpdateDictionaryFromAppcast != nil) {
            criticalUpdateDictionary = criticalUpdateDictionaryFromAppcast;
        } else if ([tags isKindOfClass:[NSArray class]] && [tags containsObject:SUAppcastElementCriticalUpdate]) {
            // Legacy path where critical update used to be a tag without a specified version
            criticalUpdateDictionary = @{};
        } else {
            // No critical info present
            criticalUpdateDictionary = nil;
        }
        
        _hasCriticalInformation = (criticalUpdateDictionary != nil);
        
        if (stateResolver != nil) {
            _state = [(SPUAppcastItemStateResolver * _Nonnull)stateResolver resolveStateWithInformationalUpdateVersions:_informationalUpdateVersions minimumOperatingSystemVersion:_minimumSystemVersion maximumOperatingSystemVersion:_maximumSystemVersion minimumAutoupdateVersion:_minimumAutoupdateVersion criticalUpdateDictionary:criticalUpdateDictionary];
        } else {
            // Note state still may be nil if a deprecated initializer is used
            _state = resolvedState;
        }
        
        NSString* rolloutIntervalString = [(NSString *)[dict objectForKey:SUAppcastElementPhasedRolloutInterval] copy];
        if (rolloutIntervalString != nil) {
            _phasedRolloutInterval = @(rolloutIntervalString.integerValue);
        }

        NSString *shortVersionString = [enclosure objectForKey:SUAppcastAttributeShortVersionString];
        if (nil == shortVersionString) {
            shortVersionString = [dict objectForKey:SUAppcastAttributeShortVersionString]; // fall back on the <item>
        }

        if (shortVersionString) {
            _displayVersionString = [shortVersionString copy];
        } else {
            _displayVersionString = [_versionString copy];
        }
        
        NSString *attributeInstallationType = [enclosure objectForKey:SUAppcastAttributeInstallationType];
        NSString *chosenInstallationType;
        if (attributeInstallationType == nil) {
            // If we have a flat package, assume installation type is guided
            // (flat / non-archived interactive packages are not supported)
            // Otherwise assume we have a normal application inside an archive
            if ([_fileURL.pathExtension isEqualToString:@"pkg"] || [_fileURL.pathExtension isEqualToString:@"mpkg"]) {
                chosenInstallationType = SPUInstallationTypeGuidedPackage;
            } else {
                chosenInstallationType = SPUInstallationTypeApplication;
            }
        } else if (!SPUValidInstallationType(attributeInstallationType)) {
            if (error != NULL) {
                *error = [NSString stringWithFormat:@"Feed item's enclosure lacks valid %@ (found %@)", SUAppcastAttributeInstallationType, attributeInstallationType];
            }
            return nil;
        } else if ([attributeInstallationType isEqualToString:SPUInstallationTypeInteractivePackage]) {
            SULog(SULogLevelDefault, @"warning: '%@' for %@ is deprecated. Use '%@' instead.", SPUInstallationTypeInteractivePackage, SUAppcastAttributeInstallationType, SPUInstallationTypeGuidedPackage);
            
            chosenInstallationType = attributeInstallationType;
        } else {
            chosenInstallationType = attributeInstallationType;
        }
        
        _installationType = [chosenInstallationType copy];

        // Find the appropriate release notes URL.
        NSString *releaseNotesString = [dict objectForKey:SUAppcastElementReleaseNotesLink];
        if (releaseNotesString) {
            NSURL *url;
            if (appcastURL != nil) {
                url = [NSURL URLWithString:releaseNotesString relativeToURL:appcastURL];
            } else {
                url = [NSURL URLWithString:releaseNotesString];
            }
            if ([url.scheme caseInsensitiveCompare:@"http"] == NSOrderedSame || [url.scheme caseInsensitiveCompare:@"https"] == NSOrderedSame) {
                _releaseNotesURL = url;
            } else {
                SULog(SULogLevelError, @"Release notes must have a http or https URL scheme.");
                _releaseNotesURL = nil;
            }
        } else if ([self.itemDescription hasPrefix:@"http://"] || [self.itemDescription hasPrefix:@"https://"]) { // if the description starts with http:// or https:// use that.
            _releaseNotesURL = [NSURL URLWithString:(NSString * _Nonnull)self.itemDescription];
        } else {
            _releaseNotesURL = nil;
        }
        
        // Get full release notes URL if informed.
        NSString *fullReleaseNotesString = [dict objectForKey:SUAppcastElementFullReleaseNotesLink];
        if (fullReleaseNotesString) {
            NSURL *url;
            if (appcastURL != nil) {
                url = [NSURL URLWithString:fullReleaseNotesString relativeToURL:appcastURL];
            } else {
                url = [NSURL URLWithString:fullReleaseNotesString];
            }
            if ([url.scheme caseInsensitiveCompare:@"http"] == NSOrderedSame || [url.scheme caseInsensitiveCompare:@"https"] == NSOrderedSame) {
                _fullReleaseNotesURL = url;
            } else {
                SULog(SULogLevelError, @"Full release notes must have a http or https URL scheme.");
                _fullReleaseNotesURL = nil;
            }
        } else {
            _fullReleaseNotesURL = nil;
        }

        NSArray *deltaDictionaries = [dict objectForKey:SUAppcastElementDeltas];
        if (deltaDictionaries) {
            NSMutableDictionary *deltas = [NSMutableDictionary dictionary];
            for (NSDictionary *deltaDictionary in deltaDictionaries) {
                NSString *deltaFrom = [deltaDictionary objectForKey:SUAppcastAttributeDeltaFrom];
                if (!deltaFrom) continue;

                NSMutableDictionary *fakeAppCastDict = [dict mutableCopy];
                [fakeAppCastDict removeObjectForKey:SUAppcastElementDeltas];
                [fakeAppCastDict setObject:deltaDictionary forKey:SURSSElementEnclosure];
                SUAppcastItem *deltaItem = [[SUAppcastItem alloc] initWithDictionary:fakeAppCastDict relativeToURL:appcastURL state:_state];

                if (deltaItem != nil) {
                    [deltas setObject:deltaItem forKey:deltaFrom];
                }
            }
            _deltaUpdates = deltas;
        }
    }
    return self;
}

@end
