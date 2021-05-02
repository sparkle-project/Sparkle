//
//  SUAppcastDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/17/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUAppcastDriver.h"
#import "SUAppcast.h"
#import "SUAppcast+Private.h"
#import "SUAppcastItem.h"
#import "SUVersionComparisonProtocol.h"
#import "SUStandardVersionComparator.h"
#import "SUOperatingSystem.h"
#import "SPUUpdaterDelegate.h"
#import "SUHost.h"
#import "SUConstants.h"
#import "SUPhasedUpdateGroupInfo.h"
#import "SULog.h"
#import "SPUDownloadDriver.h"
#import "SPUDownloadData.h"
#import "SULocalizations.h"
#import "SUErrors.h"


#include "AppKitPrevention.h"

@interface SUAppcastDriver () <SPUDownloadDriverDelegate>

@property (nonatomic, readonly) SUHost *host;
@property (nullable, nonatomic, readonly, weak) id updater;
@property (nullable, nonatomic, readonly, weak) id <SPUUpdaterDelegate> updaterDelegate;
@property (nullable, nonatomic, readonly, weak) id <SUAppcastDriverDelegate> delegate;
@property (nonatomic) SPUDownloadDriver *downloadDriver;
@property (nonatomic) BOOL includesSkippedUpdates;

@end

@implementation SUAppcastDriver

@synthesize host = _host;
@synthesize updater = _updater;
@synthesize updaterDelegate = _updaterDelegate;
@synthesize delegate = _delegate;
@synthesize downloadDriver = _downloadDriver;
@synthesize includesSkippedUpdates = _includesSkippedUpdates;

- (instancetype)initWithHost:(SUHost *)host updater:(id)updater updaterDelegate:(id <SPUUpdaterDelegate>)updaterDelegate delegate:(id <SUAppcastDriverDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _host = host;
        _updater = updater;
        _updaterDelegate = updaterDelegate;
        _delegate = delegate;
    }
    return self;
}

- (void)loadAppcastFromURL:(NSURL *)appcastURL userAgent:(NSString *)userAgent httpHeaders:(NSDictionary * _Nullable)httpHeaders inBackground:(BOOL)background includesSkippedUpdates:(BOOL)includesSkippedUpdates
{
    NSMutableDictionary *requestHTTPHeaders = [NSMutableDictionary dictionary];
    if (httpHeaders != nil) {
        [requestHTTPHeaders addEntriesFromDictionary:(NSDictionary * _Nonnull)httpHeaders];
    }
    requestHTTPHeaders[@"Accept"] = @"application/rss+xml,*/*;q=0.1";
    
    self.downloadDriver = [[SPUDownloadDriver alloc] initWithRequestURL:appcastURL host:self.host userAgent:userAgent httpHeaders:requestHTTPHeaders inBackground:background delegate:self];
    
    self.includesSkippedUpdates = includesSkippedUpdates;
    
    [self.downloadDriver downloadFile];
}

- (void)downloadDriverDidDownloadData:(SPUDownloadData *)downloadData
{
    NSError *appcastError = nil;
    SUAppcast *appcast = [[SUAppcast alloc] initWithXMLData:downloadData.data relativeToURL:downloadData.URL error:&appcastError];
    
    if (appcast == nil) {
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:SULocalizedString(@"An error occurred while parsing the update feed.", nil) forKey:NSLocalizedDescriptionKey];
        
        if (appcastError != nil) {
            [userInfo setObject:appcastError forKey:NSUnderlyingErrorKey];
        }
        
        [self.delegate didFailToFetchAppcastWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUAppcastParseError userInfo:userInfo]];
    } else {
        [self appcastDidFinishLoading:appcast inBackground:self.downloadDriver.inBackground includesSkippedUpdates:self.includesSkippedUpdates];
    }
}

- (void)downloadDriverDidFailToDownloadFileWithError:(nonnull NSError *)error
{
    SULog(SULogLevelError, @"Encountered download feed error: %@", error);

    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:@{NSLocalizedDescriptionKey:SULocalizedString(@"An error occurred in retrieving update information. Please try again later.", nil)}];
    
    if (error != nil) {
        [userInfo setObject:error forKey:NSUnderlyingErrorKey];
    }
    
    [self.delegate didFailToFetchAppcastWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUDownloadError userInfo:userInfo]];
}

- (SUAppcastItem * _Nullable)preferredUpdateForRegularAppcastItem:(SUAppcastItem * _Nullable)regularItem secondaryUpdate:(SUAppcastItem * __autoreleasing _Nullable *)secondaryUpdate
{
    SUAppcastItem *deltaItem = (regularItem != nil) ? [[self class] deltaUpdateFromAppcastItem:regularItem hostVersion:self.host.version] : nil;
    
    if (deltaItem != nil) {
        if (secondaryUpdate != NULL) {
            *secondaryUpdate = regularItem;
        }
        return deltaItem;
    } else {
        if (secondaryUpdate != NULL) {
            *secondaryUpdate = nil;
        }
        return regularItem;
    }
}

- (void)appcastDidFinishLoading:(SUAppcast *)loadedAppcast inBackground:(BOOL)background includesSkippedUpdates:(BOOL)includesSkippedUpdates
{
    [self.delegate didFinishLoadingAppcast:loadedAppcast];
    
    NSDictionary *userInfo = @{ SUUpdaterAppcastNotificationKey: loadedAppcast };
    [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterDidFinishLoadingAppCastNotification object:self.updater userInfo:userInfo];
    
    NSNumber *phasedUpdateGroup = background ? @([SUPhasedUpdateGroupInfo updateGroupForHost:self.host]) : nil;
    SUAppcast *supportedAppcast = [[self class] filterSupportedAppcast:loadedAppcast phasedUpdateGroup:phasedUpdateGroup];
    
    // Find the best valid update in the appcast by asking the delegate
    SUAppcastItem *regularItemFromDelegate;
    if ([self.updaterDelegate respondsToSelector:@selector((bestValidUpdateInAppcast:forUpdater:))]) {
        SUAppcastItem *candidateItem = [self.updaterDelegate bestValidUpdateInAppcast:supportedAppcast forUpdater:(id _Nonnull)self.updater];
        
        assert(!candidateItem.deltaUpdate);
        if (candidateItem.deltaUpdate) {
            // Client would have to go out of their way to examine the .deltaUpdates to return one
            // This is very unlikely, and we need them to give us a regular update item back
            SULog(SULogLevelError, @"Error: -bestValidUpdateInAppcast:forUpdater: cannot return a delta update item");
            regularItemFromDelegate = nil;
        } else {
            regularItemFromDelegate = candidateItem;
        }
    } else {
        regularItemFromDelegate = nil;
    }
    
    // Take care of finding best appcast item ourselves if delegate does not
    SUAppcastItem *regularItem;
    if (regularItemFromDelegate == nil) {
        regularItem = [[self class] bestItemFromAppcastItems:supportedAppcast.items comparator:[self versionComparator]];
    } else {
        regularItem = regularItemFromDelegate;
    }
    
    // Retrieve the preferred primary and secondary update items
    // In the case of a delta update, the preferred primary item will be the delta update,
    // and the secondary item will be the regular update.
    SUAppcastItem *secondaryItem = nil;
    SUAppcastItem *primaryItem = [self preferredUpdateForRegularAppcastItem:regularItem secondaryUpdate:&secondaryItem];
    
    if ([self itemContainsValidUpdate:primaryItem inBackground:background includesSkippedUpdates:includesSkippedUpdates]) {
        [self.delegate didFindValidUpdateWithAppcastItem:primaryItem secondaryAppcastItem:secondaryItem preventsAutoupdate:[self itemPreventsAutoupdate:primaryItem]];
    } else {
        NSComparisonResult hostToLatestAppcastItemComparisonResult = (primaryItem != nil) ? [[self versionComparator] compareVersion:self.host.version toVersion:primaryItem.versionString] : NSOrderedSame;
        
        [self.delegate didNotFindUpdateWithLatestAppcastItem:primaryItem hostToLatestAppcastItemComparisonResult:hostToLatestAppcastItemComparisonResult];
    }
}

// This method is used by unit tests
+ (SUAppcast *)filterSupportedAppcast:(SUAppcast *)appcast phasedUpdateGroup:(NSNumber * _Nullable)phasedUpdateGroup
{
    NSDate *currentDate = [NSDate date];
    
    return [appcast copyByFilteringItems:^(SUAppcastItem *item) {
        return (BOOL)([[self class] itemOperatingSystemIsOK:item] && [[self class] itemIsReadyForPhasedRollout:item phasedUpdateGroup:phasedUpdateGroup currentDate:currentDate]);
    }];
}

+ (SUAppcastItem * _Nullable)deltaUpdateFromAppcastItem:(SUAppcastItem *)appcastItem hostVersion:(NSString *)hostVersion
{
    return appcastItem.deltaUpdates[hostVersion];
}

+ (SUAppcastItem * _Nullable)bestItemFromAppcastItems:(NSArray *)appcastItems comparator:(id<SUVersionComparison>)comparator
{
    SUAppcastItem *item = nil;
    for(SUAppcastItem *candidate in appcastItems) {
        // Note if two items are equal, we must select the first matching one
        if (!item || [comparator compareVersion:item.versionString toVersion:candidate.versionString] == NSOrderedAscending) {
            item = candidate;
        }
    }
    return item;
}

// This method is used by unit tests
// This method should not do *any* filtering, only version comparing
+ (SUAppcastItem *)bestItemFromAppcastItems:(NSArray *)appcastItems getDeltaItem:(SUAppcastItem * __autoreleasing *)deltaItem withHostVersion:(NSString *)hostVersion comparator:(id<SUVersionComparison>)comparator
{
    SUAppcastItem *item = [self bestItemFromAppcastItems:appcastItems comparator:comparator];
    if (item != nil && deltaItem != NULL) {
        *deltaItem = [self deltaUpdateFromAppcastItem:item hostVersion:hostVersion];
    }
    return item;
}

+ (BOOL)itemOperatingSystemIsOK:(SUAppcastItem *)ui
{
    BOOL osOK = [ui isMacOsUpdate];
    
    NSString *minimumSystemVersion = ui.minimumSystemVersion;
    NSString *maximumSystemVersion = ui.maximumSystemVersion;
    
    if ((minimumSystemVersion == nil || [minimumSystemVersion isEqualToString:@""]) &&
        (maximumSystemVersion == nil || [maximumSystemVersion isEqualToString:@""])) {
        return osOK;
    }
    
    BOOL minimumVersionOK = YES;
    BOOL maximumVersionOK = YES;
    
    // We don't want to use delegate's comparator for comparing OS versions
    id<SUVersionComparison> versionComparator = [[SUStandardVersionComparator alloc] init];
    
    // Check minimum and maximum System Version
    if (minimumSystemVersion != nil && ![minimumSystemVersion isEqualToString:@""]) {
        minimumVersionOK = [versionComparator compareVersion:minimumSystemVersion toVersion:[SUOperatingSystem systemVersionString]] != NSOrderedDescending;
    }
    if (maximumSystemVersion != nil && ![maximumSystemVersion isEqualToString:@""]) {
        maximumVersionOK = [versionComparator compareVersion:maximumSystemVersion toVersion:[SUOperatingSystem systemVersionString]] != NSOrderedAscending;
    }
    
    return minimumVersionOK && maximumVersionOK && osOK;
}

- (id<SUVersionComparison>)versionComparator
{
    id<SUVersionComparison> comparator = nil;
    
    // Give the delegate a chance to provide a custom version comparator
    if ([self.updaterDelegate respondsToSelector:@selector((versionComparatorForUpdater:))]) {
        comparator = [self.updaterDelegate versionComparatorForUpdater:(id _Nonnull)self.updater];
    }
    
    // If we don't get a comparator from the delegate, use the default comparator
    if (!comparator) {
        comparator = [[SUStandardVersionComparator alloc] init];
    }
    
    return comparator;
}

- (BOOL)isItemNewer:(SUAppcastItem *)ui
{
    return ui != nil && [[self versionComparator] compareVersion:self.host.version toVersion:ui.versionString] == NSOrderedAscending;
}

- (BOOL)itemPreventsAutoupdate:(SUAppcastItem *)ui
 {
     NSString *minimumAutoupdateVersion = ui.minimumAutoupdateVersion;
     return (minimumAutoupdateVersion.length > 0 && ([[self versionComparator] compareVersion:[self.host version] toVersion:minimumAutoupdateVersion] == NSOrderedAscending));
 }

- (BOOL)itemContainsSkippedVersion:(SUAppcastItem *)ui
{
    NSString *skippedVersion = [self.host objectForUserDefaultsKey:SUSkippedVersionKey];
    if (skippedVersion == nil) { return NO; }
    
    return [[self versionComparator] compareVersion:ui.versionString toVersion:skippedVersion] != NSOrderedDescending;
}

+ (BOOL)itemIsReadyForPhasedRollout:(SUAppcastItem *)ui phasedUpdateGroup:(NSNumber * _Nullable)phasedUpdateGroup currentDate:(NSDate *)currentDate
{
    if (phasedUpdateGroup == nil || [ui isCriticalUpdate]) {
        return YES;
    }
    
    NSNumber *phasedRolloutIntervalObject = [ui phasedRolloutInterval];
    if (phasedRolloutIntervalObject == nil) {
        return YES;
    }
    
    NSDate* itemReleaseDate = ui.date;
    if (itemReleaseDate == nil) {
        return YES;
    }
    
    NSTimeInterval timeSinceRelease = [currentDate timeIntervalSinceDate:itemReleaseDate];
    
    NSTimeInterval phasedRolloutInterval = [phasedRolloutIntervalObject doubleValue];
    NSTimeInterval timeToWaitForGroup = phasedRolloutInterval * phasedUpdateGroup.unsignedIntegerValue;
    
    if (timeSinceRelease >= timeToWaitForGroup) {
        return YES;
    }
    
    return NO;
}

- (BOOL)itemContainsValidUpdate:(SUAppcastItem *)ui inBackground:(BOOL)background includesSkippedUpdates:(BOOL)includesSkippedUpdates
{
    if (ui == nil) {
        return NO;
    }
    
    // Check that we have a newer appcast item than host
    if (![self isItemNewer:ui]) {
        return NO;
    }
    
    // Check for skipped updates
    if (!includesSkippedUpdates && [self itemContainsSkippedVersion:ui]) {
        return NO;
    }
    
    return YES;
}

- (void)cleanup:(void (^)(void))completionHandler
{
    if (self.downloadDriver == nil) {
        completionHandler();
    } else {
        [self.downloadDriver cleanup:completionHandler];
    }
}

@end
