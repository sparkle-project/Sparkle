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

#define DELTA_EXPECTED_LOCALES_LIMIT 15

static NSString *SUAppcastItemDeltaUpdatesKey = @"deltaUpdates";
static NSString *SUAppcastItemDisplayVersionStringKey = @"displayVersionString";
static NSString *SUAppcastItemSignaturesKey = @"signatures";
static NSString *SUAppcastItemFileURLKey = @"fileURL";
static NSString *SUAppcastItemInfoURLKey = @"infoURL";
static NSString *SUAppcastItemContentLengthKey = @"contentLength";
static NSString *SUAppcastItemDescriptionKey = @"itemDescription";
static NSString *SUAppcastItemDescriptionFormatKey = @"itemDescriptionFormat";
static NSString *SUAppcastItemMaximumSystemVersionKey = @"maximumSystemVersion";
static NSString *SUAppcastItemMinimumSystemVersionKey = @"minimumSystemVersion";
static NSString *SUAppcastItemReleaseNotesURLKey = @"releaseNotesURL";
static NSString *SUAppcastItemFullReleaseNotesURLKey = @"fullReleaseNotesURL";
static NSString *SUAppcastItemTitleKey = @"title";
static NSString *SUAppcastItemVersionStringKey = @"versionString";
static NSString *SUAppcastItemPropertiesKey = @"propertiesDictionary";
static NSString *SUAppcastItemInstallationTypeKey = @"SUAppcastItemInstallationType";
static NSString *SUAppcastItemStateKey = @"SUAppcastItemState";
static NSString *SUAppcastItemDeltaFromSparkleExecutableSizeKey = @"SUAppcastItemDeltaFromSparkleExecutableSize";
static NSString *SUAppcastItemDeltaFromSparkleLocalesKey = @"SUAppcastItemDeltaFromSparkleLocales";

@interface SUAppcastItem ()

@property (readonly, nonatomic, nullable) SUSignatures *signatures;

@end

@implementation SUAppcastItem
{
    // Auxiliary appcast item state that needs to be evaluated based on the host state
    // This may be nil if the client creates an SUAppcastItem with a deprecated initializer
    // In that case we will need to fallback to safe behavior
    SPUAppcastItemState *_state;
    
    // Indicates if we have any critical information. Used as a fallback if state is nil
    BOOL _hasCriticalInformation;
    
    // Indicates the versions we update from that are informational-only
    NSSet<NSString *> *_informationalUpdateVersions;
}

@synthesize dateString = _dateString;
@synthesize deltaUpdates = _deltaUpdates;
@synthesize displayVersionString = _displayVersionString;
@synthesize signatures = _signatures;
@synthesize fileURL = _fileURL;
@synthesize contentLength = _contentLength;
@synthesize infoURL = _infoURL;
@synthesize itemDescription = _itemDescription;
@synthesize itemDescriptionFormat = _itemDescriptionFormat;
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
@synthesize ignoreSkippedUpgradesBelowVersion = _ignoreSkippedUpgradesBelowVersion;
@synthesize phasedRolloutInterval = _phasedRolloutInterval;
@synthesize channel = _channel;
@synthesize deltaFromSparkleExecutableSize = _deltaFromSparkleExecutableSize;
@synthesize deltaFromSparkleLocales = _deltaFromSparkleLocales;

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)decoder
{
    self = [super init];
    
    if (self != nil) {
        _deltaUpdates = [decoder decodeObjectOfClasses:[NSSet setWithArray:@[[NSDictionary class], [SUAppcastItem class], [NSString class]]] forKey:SUAppcastItemDeltaUpdatesKey];
        _deltaFromSparkleExecutableSize = [decoder decodeObjectOfClass:[NSNumber class] forKey:SUAppcastItemDeltaFromSparkleExecutableSizeKey];
        _deltaFromSparkleLocales = [decoder decodeObjectOfClasses:[NSSet setWithArray:@[[NSSet class], [NSString class]]] forKey:SUAppcastItemDeltaFromSparkleLocalesKey];
        
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
        _itemDescriptionFormat = [(NSString *)[decoder decodeObjectOfClass:[NSString class] forKey:SUAppcastItemDescriptionFormatKey] copy];
        _maximumSystemVersion = [(NSString *)[decoder decodeObjectOfClass:[NSString class] forKey:SUAppcastItemMaximumSystemVersionKey] copy];
        _minimumSystemVersion = [(NSString *)[decoder decodeObjectOfClass:[NSString class] forKey:SUAppcastItemMinimumSystemVersionKey] copy];
        _minimumAutoupdateVersion = [(NSString *)[decoder decodeObjectOfClass:[NSString class] forKey:SUAppcastElementMinimumAutoupdateVersion] copy];
        _ignoreSkippedUpgradesBelowVersion = [(NSString *)[decoder decodeObjectOfClass:[NSString class] forKey:SUAppcastElementIgnoreSkippedUpgradesBelowVersion] copy];
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
    if (_deltaUpdates != nil) {
        [encoder encodeObject:_deltaUpdates forKey:SUAppcastItemDeltaUpdatesKey];
    }
    
    if (_deltaFromSparkleExecutableSize != nil) {
        [encoder encodeObject:_deltaFromSparkleExecutableSize forKey:SUAppcastItemDeltaFromSparkleExecutableSizeKey];
    }
    
    if (_deltaFromSparkleLocales != nil) {
        [encoder encodeObject:_deltaFromSparkleLocales forKey:SUAppcastItemDeltaFromSparkleLocalesKey];
    }
    
    if (_displayVersionString != nil) {
        [encoder encodeObject:_displayVersionString forKey:SUAppcastItemDisplayVersionStringKey];
    }
    
    if (_signatures != nil) {
        [encoder encodeObject:_signatures forKey:SUAppcastItemSignaturesKey];
    }
    
    if (_fileURL != nil) {
        [encoder encodeObject:_fileURL forKey:SUAppcastItemFileURLKey];
    }
    
    if (_infoURL != nil) {
        [encoder encodeObject:_infoURL forKey:SUAppcastItemInfoURLKey];
    }
    
    [encoder encodeInt64:(int64_t)_contentLength forKey:SUAppcastItemContentLengthKey];
    
    if (_itemDescription != nil) {
        [encoder encodeObject:_itemDescription forKey:SUAppcastItemDescriptionKey];
    }
    
    if (_itemDescriptionFormat != nil) {
        [encoder encodeObject:_itemDescriptionFormat forKey:SUAppcastItemDescriptionFormatKey];
    }
    
    if (_maximumSystemVersion != nil) {
        [encoder encodeObject:_maximumSystemVersion forKey:SUAppcastItemMaximumSystemVersionKey];
    }
    
    if (_minimumSystemVersion != nil) {
        [encoder encodeObject:_minimumSystemVersion forKey:SUAppcastItemMinimumSystemVersionKey];
    }
    
    if (_minimumAutoupdateVersion != nil) {
        [encoder encodeObject:_minimumAutoupdateVersion forKey:SUAppcastElementMinimumAutoupdateVersion];
    }
    
    if (_ignoreSkippedUpgradesBelowVersion != nil) {
        [encoder encodeObject:_ignoreSkippedUpgradesBelowVersion forKey:SUAppcastElementIgnoreSkippedUpgradesBelowVersion];
    }
    
    if (_state != nil) {
        [encoder encodeObject:_state forKey:SUAppcastItemStateKey];
    }
    
    if (_releaseNotesURL != nil) {
        [encoder encodeObject:_releaseNotesURL forKey:SUAppcastItemReleaseNotesURLKey];
    }
    
    if (_fullReleaseNotesURL != nil) {
        [encoder encodeObject:_fullReleaseNotesURL forKey:SUAppcastItemFullReleaseNotesURLKey];
    }
    
    if (_title != nil) {
        [encoder encodeObject:_title forKey:SUAppcastItemTitleKey];
    }
    
    if (_versionString != nil) {
        [encoder encodeObject:_versionString forKey:SUAppcastItemVersionStringKey];
    }
    
    if (_osString != nil) {
        [encoder encodeObject:_osString forKey:SUAppcastAttributeOsType];
    }
    
    if (_propertiesDictionary != nil) {
        [encoder encodeObject:_propertiesDictionary forKey:SUAppcastItemPropertiesKey];
    }
    
    if (_installationType != nil) {
        [encoder encodeObject:_installationType forKey:SUAppcastItemInstallationTypeKey];
    }
    
    if (_phasedRolloutInterval != nil) {
        [encoder encodeObject:_phasedRolloutInterval forKey:SUAppcastElementPhasedRolloutInterval];
    }
    
    if (_channel != nil) {
        [encoder encodeObject:_channel forKey:SUAppcastElementChannel];
    }
}

- (BOOL)isDeltaUpdate
{
    NSDictionary *rssElementEnclosure = [_propertiesDictionary objectForKey:SURSSElementEnclosure];
    return [rssElementEnclosure objectForKey:SUAppcastAttributeDeltaFrom] != nil;
}

- (BOOL)isCriticalUpdate
{
    if (_state != nil) {
        return _state.criticalUpdate;
    } else {
        return _hasCriticalInformation;
    }
}

- (BOOL)isMajorUpgrade
{
    if (_state != nil) {
        return _state.majorUpgrade;
    } else {
        return NO;
    }
}

- (BOOL)minimumOperatingSystemVersionIsOK
{
    if (_state != nil) {
        return _state.minimumOperatingSystemVersionIsOK;
    } else {
        return YES;
    }
}

- (BOOL)maximumOperatingSystemVersionIsOK
{
    if (_state != nil) {
        return _state.maximumOperatingSystemVersionIsOK;
    } else {
        return YES;
    }
}

- (BOOL)isMacOsUpdate
{
    return _osString == nil || [_osString isEqualToString:SUAppcastAttributeValueMacOS];
}

- (NSDate *)date
{
    NSString *dateString = _dateString;
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
    if (_state != nil) {
        return _state.informationalUpdate;
    } else {
        return (_informationalUpdateVersions != nil && _informationalUpdateVersions.count == 0);
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
- (nullable instancetype)initWithDictionary:(NSDictionary *)dict relativeToURL:(NSURL * _Nullable)appcastURL state:(SPUAppcastItemState * _Nullable)state SPU_OBJC_DIRECT
{
    return [self initWithDictionary:dict relativeToURL:appcastURL stateResolver:nil resolvedState:state failureReason:nil];
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
        
        id itemDescription = [dict objectForKey:SURSSElementDescription];
        if (itemDescription != nil) {
            if ([(NSObject *)itemDescription isKindOfClass:[NSDictionary class]]) {
                NSString *descriptionContent = itemDescription[@"content"];
                NSString *itemDescriptionString;
                if ([descriptionContent isKindOfClass:[NSString class]]) {
                    itemDescriptionString = [descriptionContent copy];
                } else {
                    itemDescriptionString = nil;
                }
                
                id descriptionFormat = itemDescription[@"format"];
                NSString *descriptionFormatString;
                if ([(NSObject *)descriptionFormat isKindOfClass:[NSString class]]) {
                    descriptionFormatString = [(NSString *)descriptionFormat lowercaseString];
                } else {
                    descriptionFormatString = nil;
                }
                
                _itemDescription = itemDescriptionString;
                if (itemDescriptionString != nil) {
                    if (descriptionFormatString != nil) {
                        if (![descriptionFormatString isEqualToString:@"plain-text"] &&
                            ![descriptionFormatString isEqualToString:@"markdown"] &&
                            ![descriptionFormatString isEqualToString:@"html"]) {
                            SULog(SULogLevelError, @"warning: Item '%@' has unknown format '%@' in '<%@>'. Ignoring and using 'html' instead.", _title, descriptionFormatString, SUAppcastItemDescriptionKey);
                            
                            _itemDescriptionFormat = @"html";
                        } else {
                            _itemDescriptionFormat = descriptionFormatString;
                        }
                    } else {
                        _itemDescriptionFormat = @"html";
                    }
                } else {
                    _itemDescriptionFormat = nil;
                }
            } else if ([(NSObject *)itemDescription isKindOfClass:[NSString class]]) {
                // Legacy path
                _itemDescription = [(NSString *)itemDescription copy];
                _itemDescriptionFormat = @"html";
            }
        } else {
            _itemDescription = nil;
            _itemDescriptionFormat = nil;
        }

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
                if (error) {
                    *error = @"File URLs must have a http or https URL scheme";
                }
                return nil;
            }
        }
        if (enclosure) {
            _signatures = [[SUSignatures alloc] initWithEd:[enclosure objectForKey:SUAppcastAttributeEDSignature]
#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
                                                       dsa:[enclosure objectForKey:SUAppcastAttributeDSASignature]
#endif
            ];
            _osString = [enclosure objectForKey:SUAppcastAttributeOsType];
        }

        _versionString = [(NSString *)newVersion copy];
        _minimumSystemVersion = [(NSString *)[dict objectForKey:SUAppcastElementMinimumSystemVersion] copy];
        _maximumSystemVersion = [(NSString *)[dict objectForKey:SUAppcastElementMaximumSystemVersion] copy];
        _minimumAutoupdateVersion = [(NSString *)[dict objectForKey:SUAppcastElementMinimumAutoupdateVersion] copy];
        
        _ignoreSkippedUpgradesBelowVersion = [(NSString *)[dict objectForKey:SUAppcastElementIgnoreSkippedUpgradesBelowVersion] copy];
        
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
        
        NSString *chosenInstallationType;
#if SPARKLE_BUILD_PACKAGE_SUPPORT
        NSString *attributeInstallationType = [enclosure objectForKey:SUAppcastAttributeInstallationType];
        if (attributeInstallationType == nil) {
            // If we have a flat package, assume installation type is guided
            // (flat / non-archived interactive packages are not supported)
            // Otherwise assume we have a normal application inside an archive
            if ([_fileURL.pathExtension isEqualToString:@"pkg"] || [_fileURL.pathExtension isEqualToString:@"mpkg"]) {
                chosenInstallationType = SPUInstallationTypeGuidedPackage;
            } else
            {
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
#else
        chosenInstallationType = SPUInstallationTypeApplication;
#endif
        
        _installationType = [chosenInstallationType copy];
        
        NSString *enclosureDeltaSparkleExecutableSize = [enclosure objectForKey:SUAppcastAttributeDeltaFromSparkleExecutableSize];
        if (enclosureDeltaSparkleExecutableSize != nil) {
            long long sparkleExecutableSize = [enclosureDeltaSparkleExecutableSize longLongValue];
            if (sparkleExecutableSize > 0) {
                _deltaFromSparkleExecutableSize = @(sparkleExecutableSize);
            }
        }
        
        NSString *enclosureDeltaSparkleLocales = [enclosure objectForKey:SUAppcastAttributeDeltaFromSparkleLocales];
        if (enclosureDeltaSparkleLocales != nil) {
            NSMutableSet<NSString *> *expectedLocales = [NSMutableSet set];
            
            NSArray<NSString *> *locales = [enclosureDeltaSparkleLocales componentsSeparatedByString:@","];
            NSUInteger localeIndex = 0;
            for (NSString *locale in locales) {
                if (locale.length != 0 && ![locale containsString:@"."] && ![locale containsString:@"/"]) {
                    [expectedLocales addObject:locale];
                    localeIndex++;
                    
                    // Place an upper limit on the number of locales we process
                    if (localeIndex >= DELTA_EXPECTED_LOCALES_LIMIT) {
                        break;
                    }
                } else {
                    SULog(SULogLevelError, @"Ignoring expected delta locale '%@' because it contains a period or slash or is empty", locale);
                }
            }
            
            _deltaFromSparkleLocales = [expectedLocales copy];
        }

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
        } else if ([_itemDescription hasPrefix:@"http://"] || [_itemDescription hasPrefix:@"https://"]) { // if the description starts with http:// or https:// use that.
            _releaseNotesURL = [NSURL URLWithString:(NSString * _Nonnull)_itemDescription];
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
