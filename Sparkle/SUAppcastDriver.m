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
#import "SUAppcastItem+Private.h"
#import "SUVersionComparisonProtocol.h"
#import "SUStandardVersionComparator.h"
#import "SUOperatingSystem.h"
#import "SPUUpdaterDelegate.h"
#import "SUHost.h"
#import "SPUSkippedUpdate.h"
#import "SUConstants.h"
#import "SUPhasedUpdateGroupInfo.h"
#import "SULog.h"
#import "SPUDownloadDriver.h"
#import "SPUDownloadData.h"
#import "SULocalizations.h"
#import "SUErrors.h"
#import "SPUAppcastItemStateResolver.h"
#import "SPUAppcastItemStateResolver+Private.h"
#import "SPUAppcastItemState.h"


#include "AppKitPrevention.h"

@interface SUAppcastDriver () <SPUDownloadDriverDelegate>

@property (nonatomic, readonly) SUHost *host;
@property (nonatomic, readonly, weak) id updater;
@property (nullable, nonatomic, readonly, weak) id <SPUUpdaterDelegate> updaterDelegate;
@property (nullable, nonatomic, readonly, weak) id <SUAppcastDriverDelegate> delegate;
@property (nonatomic) SPUDownloadDriver *downloadDriver;

@end

@implementation SUAppcastDriver

@synthesize host = _host;
@synthesize updater = _updater;
@synthesize updaterDelegate = _updaterDelegate;
@synthesize delegate = _delegate;
@synthesize downloadDriver = _downloadDriver;

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

- (void)loadAppcastFromURL:(NSURL *)appcastURL userAgent:(NSString *)userAgent httpHeaders:(NSDictionary * _Nullable)httpHeaders inBackground:(BOOL)background
{
    NSMutableDictionary *requestHTTPHeaders = [NSMutableDictionary dictionary];
    if (httpHeaders != nil) {
        [requestHTTPHeaders addEntriesFromDictionary:(NSDictionary * _Nonnull)httpHeaders];
    }
    requestHTTPHeaders[@"Accept"] = @"application/rss+xml,*/*;q=0.1";
    
    self.downloadDriver = [[SPUDownloadDriver alloc] initWithRequestURL:appcastURL host:self.host userAgent:userAgent httpHeaders:requestHTTPHeaders inBackground:background delegate:self];
    
    [self.downloadDriver downloadFile];
}

- (void)downloadDriverDidDownloadData:(SPUDownloadData *)downloadData
{
    SPUAppcastItemStateResolver *stateResolver = [[SPUAppcastItemStateResolver alloc] initWithHostVersion:self.host.version applicationVersionComparator:[self versionComparator] standardVersionComparator:[SUStandardVersionComparator defaultComparator]];
 
    NSError *appcastError = nil;
    SUAppcast *appcast = [[SUAppcast alloc] initWithXMLData:downloadData.data relativeToURL:downloadData.URL stateResolver:stateResolver error:&appcastError];
    
    if (appcast == nil) {
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:SULocalizedString(@"An error occurred while parsing the update feed.", nil) forKey:NSLocalizedDescriptionKey];
        
        if (appcastError != nil) {
            [userInfo setObject:appcastError forKey:NSUnderlyingErrorKey];
        }
        
        [self.delegate didFailToFetchAppcastWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUAppcastParseError userInfo:userInfo]];
    } else {
        [self appcastDidFinishLoading:appcast inBackground:self.downloadDriver.inBackground];
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

- (SUAppcastItem *)retrieveBestAppcastItemFromAppcast:(SUAppcast *)appcast versionComparator:(id<SUVersionComparison>)versionComparator secondaryUpdate:(SUAppcastItem * __autoreleasing _Nullable *)secondaryAppcastItem
{
    // Find the best valid update in the appcast by asking the delegate
    // Don't ask the delegate if the appcast has no items though
    SUAppcastItem *regularItemFromDelegate;
    BOOL delegateOptedOutOfSelection;
    if (appcast.items.count > 0 && [self.updaterDelegate respondsToSelector:@selector((bestValidUpdateInAppcast:forUpdater:))]) {
        SUAppcastItem *candidateItem = [self.updaterDelegate bestValidUpdateInAppcast:appcast forUpdater:(id _Nonnull)self.updater];
        
        if (candidateItem == SUAppcastItem.emptyAppcastItem) {
            regularItemFromDelegate = nil;
            delegateOptedOutOfSelection = YES;
        } else if (candidateItem == nil) {
            regularItemFromDelegate = nil;
            delegateOptedOutOfSelection = NO;
        } else {
            assert(!candidateItem.deltaUpdate);
            if (candidateItem.deltaUpdate) {
                // Client would have to go out of their way to examine the .deltaUpdates to return one
                // We need them to give us a regular update item back instead..
                SULog(SULogLevelError, @"Error: -bestValidUpdateInAppcast:forUpdater: cannot return a delta update item");
                regularItemFromDelegate = nil;
            } else {
                regularItemFromDelegate = candidateItem;
            }
            
            delegateOptedOutOfSelection = NO;
        }
    } else {
        regularItemFromDelegate = nil;
        delegateOptedOutOfSelection = NO;
    }
    
    // Take care of finding best appcast item ourselves if delegate does not
    SUAppcastItem *regularItem;
    if (regularItemFromDelegate == nil && !delegateOptedOutOfSelection) {
        regularItem = [[self class] bestItemFromAppcastItems:appcast.items comparator:versionComparator];
    } else {
        regularItem = regularItemFromDelegate;
    }
    
    // Retrieve the preferred primary and secondary update items
    // In the case of a delta update, the preferred primary item will be the delta update,
    // and the secondary item will be the regular update.
    return [self preferredUpdateForRegularAppcastItem:regularItem secondaryUpdate:secondaryAppcastItem];
}

- (void)appcastDidFinishLoading:(SUAppcast *)loadedAppcast inBackground:(BOOL)background
{
    [self.delegate didFinishLoadingAppcast:loadedAppcast];
    
    NSDictionary *userInfo = @{ SUUpdaterAppcastNotificationKey: loadedAppcast };
    [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterDidFinishLoadingAppCastNotification object:self.updater userInfo:userInfo];
    
    NSSet<NSString *> *allowedChannels;
    if ([self.updaterDelegate respondsToSelector:@selector(allowedChannelsForUpdater:)]) {
        allowedChannels = [self.updaterDelegate allowedChannelsForUpdater:self.updater];
        if (allowedChannels == nil) {
            SULog(SULogLevelError, @"Error: -allowedChannelsForUpdater: cannot return nil. Treating this as an empty set.");
            allowedChannels = [NSSet set];
        }
    } else {
        allowedChannels = [NSSet set];
    }
    
    SUAppcast *macOSAppcast = [[self class] filterAppcast:loadedAppcast forMacOSAndAllowedChannels:allowedChannels];
    
    id<SUVersionComparison> applicationVersionComparator = [self versionComparator];
    
    NSNumber *phasedUpdateGroup = background ? @([SUPhasedUpdateGroupInfo updateGroupForHost:self.host]) : nil;
    
    SPUSkippedUpdate *skippedUpdate = background ? [SPUSkippedUpdate skippedUpdateForHost:self.host] : nil;
    
    NSDate *currentDate = [NSDate date];
    
    // First filter out min/max OS version and see if there's an update that passes
    // the minimum autoupdate version. We filter out updates that fail the minimum
    // autoupdate version test because we have a preference over minor updates that can be
    // downloaded and installed with less disturbance
    SUAppcast *passesMinimumAutoupdateAppcast = [[self class] filterSupportedAppcast:macOSAppcast phasedUpdateGroup:phasedUpdateGroup skippedUpdate:skippedUpdate currentDate:currentDate hostVersion:self.host.version versionComparator:applicationVersionComparator testOSVersion:YES testMinimumAutoupdateVersion:YES];
    
    SUAppcastItem *secondaryItemPassesMinimumAutoupdate = nil;
    SUAppcastItem *primaryItemPassesMinimumAutoupdate = [self retrieveBestAppcastItemFromAppcast:passesMinimumAutoupdateAppcast versionComparator:applicationVersionComparator secondaryUpdate:&secondaryItemPassesMinimumAutoupdate];
    
    // If we weren't able to find a valid update, try to find an update that
    // doesn't pass the minimum autoupdate version
    SUAppcastItem *finalPrimaryItem;
    SUAppcastItem *finalSecondaryItem = nil;
    if (![self isItemNewer:primaryItemPassesMinimumAutoupdate]) {
        SUAppcast *failsMinimumAutoupdateAppcast = [[self class] filterSupportedAppcast:macOSAppcast phasedUpdateGroup:phasedUpdateGroup skippedUpdate:skippedUpdate currentDate:currentDate hostVersion:self.host.version versionComparator:applicationVersionComparator testOSVersion:YES testMinimumAutoupdateVersion:NO];
        
        finalPrimaryItem = [self retrieveBestAppcastItemFromAppcast:failsMinimumAutoupdateAppcast versionComparator:applicationVersionComparator secondaryUpdate:&finalSecondaryItem];
    } else {
        finalPrimaryItem = primaryItemPassesMinimumAutoupdate;
        finalSecondaryItem = secondaryItemPassesMinimumAutoupdate;
    }
    
    if ([self isItemNewer:finalPrimaryItem]) {
        // We found a suitable update
        [self.delegate didFindValidUpdateWithAppcastItem:finalPrimaryItem secondaryAppcastItem:finalSecondaryItem];
    } else {
        // Find the latest appcast item that we can report to the user and updater delegates
        // This may include updates that fail due to OS version requirements.
        // This excludes newer backgrounded updates that fail because they are skipped or not in current phased rollout group
        SUAppcast *notFoundAppcast = [[self class] filterSupportedAppcast:macOSAppcast phasedUpdateGroup:phasedUpdateGroup skippedUpdate:skippedUpdate currentDate:currentDate hostVersion:self.host.version versionComparator:applicationVersionComparator testOSVersion:NO testMinimumAutoupdateVersion:NO];
        
        SUAppcastItem *notFoundPrimaryItem = [self retrieveBestAppcastItemFromAppcast:notFoundAppcast versionComparator:applicationVersionComparator secondaryUpdate:nil];
        
        NSComparisonResult hostToLatestAppcastItemComparisonResult;
        if (notFoundPrimaryItem != nil) {
            hostToLatestAppcastItemComparisonResult = [applicationVersionComparator compareVersion:self.host.version toVersion:notFoundPrimaryItem.versionString];
        } else {
            hostToLatestAppcastItemComparisonResult = 0;
        }
        
        [self.delegate didNotFindUpdateWithLatestAppcastItem:notFoundPrimaryItem hostToLatestAppcastItemComparisonResult:hostToLatestAppcastItemComparisonResult background:background];
    }
}

// This method is used by unit tests
+ (SUAppcast *)filterAppcast:(SUAppcast *)appcast forMacOSAndAllowedChannels:(NSSet<NSString *> *)allowedChannels
{
    return [appcast copyByFilteringItems:^(SUAppcastItem *item) {
        // We will never care about other OS's
        BOOL macOSUpdate = [item isMacOsUpdate];
        if (!macOSUpdate) {
            return NO;
        }
        
        NSString *channel = item.channel;
        if (channel == nil) {
            // Item is on the default channel
            return YES;
        }
        
        return [allowedChannels containsObject:channel];
    }];
}

// This method is used by unit tests
+ (SUAppcast *)filterSupportedAppcast:(SUAppcast *)appcast phasedUpdateGroup:(NSNumber * _Nullable)phasedUpdateGroup skippedUpdate:(SPUSkippedUpdate * _Nullable)skippedUpdate currentDate:(NSDate *)currentDate hostVersion:(NSString *)hostVersion versionComparator:(id<SUVersionComparison>)versionComparator testOSVersion:(BOOL)testOSVersion testMinimumAutoupdateVersion:(BOOL)testMinimumAutoupdateVersion
{
    BOOL hostPassesSkippedMajorVersion = [SPUAppcastItemStateResolver isMinimumAutoupdateVersionOK:skippedUpdate.majorVersion hostVersion:hostVersion versionComparator:versionComparator];
    
    return [appcast copyByFilteringItems:^(SUAppcastItem *item) {
        BOOL passesOSVersion = (!testOSVersion || (item.minimumOperatingSystemVersionIsOK && item.maximumOperatingSystemVersionIsOK));
        
        BOOL passesPhasedRollout = [self itemIsReadyForPhasedRollout:item phasedUpdateGroup:phasedUpdateGroup currentDate:currentDate hostVersion:hostVersion versionComparator:versionComparator];
        
        BOOL passesMinimumAutoupdateVersion = (!testMinimumAutoupdateVersion || !item.majorUpgrade);
        
        BOOL passesSkippedUpdates = (versionComparator == nil || hostVersion == nil || ![self item:item containsSkippedUpdate:skippedUpdate hostPassesSkippedMajorVersion:hostPassesSkippedMajorVersion versionComparator:versionComparator]);
        
        return (BOOL)(passesOSVersion && passesPhasedRollout && passesMinimumAutoupdateVersion && passesSkippedUpdates);
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

- (id<SUVersionComparison>)versionComparator
{
    id<SUVersionComparison> comparator = nil;
    
    // Give the delegate a chance to provide a custom version comparator
    if ([self.updaterDelegate respondsToSelector:@selector((versionComparatorForUpdater:))]) {
        comparator = [self.updaterDelegate versionComparatorForUpdater:self.updater];
    }
    
    // If we don't get a comparator from the delegate, use the default comparator
    if (comparator == nil) {
        comparator = [SUStandardVersionComparator defaultComparator];
    }
    
    return comparator;
}

- (BOOL)isItemNewer:(SUAppcastItem *)ui
{
    return ui != nil && [[self versionComparator] compareVersion:self.host.version toVersion:ui.versionString] == NSOrderedAscending;
}

+ (BOOL)item:(SUAppcastItem *)ui containsSkippedUpdate:(SPUSkippedUpdate * _Nullable)skippedUpdate hostPassesSkippedMajorVersion:(BOOL)hostPassesSkippedMajorVersion versionComparator:(id<SUVersionComparison>)versionComparator
{
    NSString *skippedMajorVersion = skippedUpdate.majorVersion;
    
    if (!hostPassesSkippedMajorVersion && skippedMajorVersion != nil && [versionComparator compareVersion:skippedMajorVersion toVersion:ui.versionString] != NSOrderedDescending) {
        // Item is on a greater or equal version than a major version we've skipped
        // So we skip this item
        return YES;
    }
    
    NSString *skippedMinorVersion = skippedUpdate.minorVersion;
    
    if (skippedMinorVersion != nil && [versionComparator compareVersion:skippedMinorVersion toVersion:ui.versionString] != NSOrderedAscending) {
        // Item is on a less or equal version than a minor version we've skipped
        // So we skip this item
        return YES;
    }
    
    return NO;
}

+ (BOOL)itemIsReadyForPhasedRollout:(SUAppcastItem *)ui phasedUpdateGroup:(NSNumber * _Nullable)phasedUpdateGroup currentDate:(NSDate *)currentDate hostVersion:(NSString *)hostVersion versionComparator:(id<SUVersionComparison>)versionComparator
{
    if (phasedUpdateGroup == nil || ui.criticalUpdate) {
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

- (void)cleanup:(void (^)(void))completionHandler
{
    if (self.downloadDriver == nil) {
        completionHandler();
    } else {
        [self.downloadDriver cleanup:completionHandler];
    }
}

@end
