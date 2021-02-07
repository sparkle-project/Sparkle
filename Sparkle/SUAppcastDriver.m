//
//  SUAppcastDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/17/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUAppcastDriver.h"
#import "SUAppcast.h"
#import "SUAppcastItem.h"
#import "SUVersionComparisonProtocol.h"
#import "SUStandardVersionComparator.h"
#import "SUOperatingSystem.h"
#import "SPUUpdaterDelegate.h"
#import "SUHost.h"
#import "SUConstants.h"
#import "SUPhasedUpdateGroupInfo.h"


#include "AppKitPrevention.h"

@interface SUAppcastDriver ()

@property (nonatomic, readonly) SUHost *host;
@property (nonatomic, copy) NSString *userAgent;
@property (nullable, nonatomic, readonly, weak) id updater;
@property (nullable, nonatomic, readonly, weak) id <SPUUpdaterDelegate> updaterDelegate;
@property (nullable, nonatomic) SUAppcastItem *nonDeltaUpdateItem;
@property (nullable, nonatomic, readonly, weak) id <SUAppcastDriverDelegate> delegate;

@end

@implementation SUAppcastDriver

@synthesize host = _host;
@synthesize userAgent = _userAgent;
@synthesize updater = _updater;
@synthesize updaterDelegate = _updaterDelegate;
@synthesize nonDeltaUpdateItem = _nonDeltaUpdateItem;
@synthesize delegate = _delegate;

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
    self.userAgent = userAgent;
    
    SUAppcast *appcast = [[SUAppcast alloc] init];
    [appcast setUserAgentString:userAgent];
    [appcast setHttpHeaders:httpHeaders];
    [appcast fetchAppcastFromURL:appcastURL inBackground:background completionBlock:^(NSError *error) {
        if (error != nil) {
            [self.delegate didFailToFetchAppcastWithError:error];
        } else {
            [self appcastDidFinishLoading:appcast inBackground:background includesSkippedUpdates:includesSkippedUpdates];
        }
    }];
}

- (void)appcastDidFinishLoading:(SUAppcast *)loadedAppcast inBackground:(BOOL)background includesSkippedUpdates:(BOOL)includesSkippedUpdates
{
    [self.delegate didFinishLoadingAppcast:loadedAppcast];
    
    NSDictionary *userInfo = @{ SUUpdaterAppcastNotificationKey: loadedAppcast };
    [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterDidFinishLoadingAppCastNotification object:self.updater userInfo:userInfo];
    
    NSNumber *phasedUpdateGroup = background ? @([SUPhasedUpdateGroupInfo updateGroupForHost:self.host]) : nil;
    SUAppcast *supportedAppcast = [[self class] filterSupportedAppcast:loadedAppcast phasedUpdateGroup:phasedUpdateGroup];
    
    SUAppcastItem *item = nil;
    SUAppcastItem *nonDeltaUpdateItem = nil;
    
    // Now we have to find the best valid update in the appcast.
    if ([self.updaterDelegate respondsToSelector:@selector((bestValidUpdateInAppcast:forUpdater:))])
    {
        item = [self.updaterDelegate bestValidUpdateInAppcast:supportedAppcast forUpdater:(id _Nonnull)self.updater];
    }
    
    if (item != nil)
    {
        // Does the delegate want to handle it?
        if ([item isDeltaUpdate]) {
            nonDeltaUpdateItem = [self.updaterDelegate bestValidUpdateInAppcast:[supportedAppcast copyWithoutDeltaUpdates] forUpdater:(id _Nonnull)self.updater];
        }
    }
    else // If not, we'll take care of it ourselves.
    {
        // Find the best supported update
        SUAppcastItem *deltaUpdateItem = nil;
        item = [[self class] bestItemFromAppcastItems:supportedAppcast.items getDeltaItem:&deltaUpdateItem withHostVersion:self.host.version comparator:[self versionComparator]];
        
        if (item && deltaUpdateItem) {
            nonDeltaUpdateItem = item;
            item = deltaUpdateItem;
        }
    }
    
    if ([self itemContainsValidUpdate:item inBackground:background includesSkippedUpdates:includesSkippedUpdates]) {
        self.nonDeltaUpdateItem = nonDeltaUpdateItem;
        [self.delegate didFindValidUpdateWithAppcastItem:item preventsAutoupdate:[self itemPreventsAutoupdate:item]];
    } else {
        NSComparisonResult hostToLatestAppcastItemComparisonResult = (item != nil) ? [[self versionComparator] compareVersion:[self.host version] toVersion:[item versionString]] : 0;
        [self.delegate didNotFindUpdateWithLatestAppcastItem:item hostToLatestAppcastItemComparisonResult:hostToLatestAppcastItemComparisonResult];
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

// This method is used by unit tests
// This method should not do *any* filtering, only version comparing
+ (SUAppcastItem *)bestItemFromAppcastItems:(NSArray *)appcastItems getDeltaItem:(SUAppcastItem * __autoreleasing *)deltaItem withHostVersion:(NSString *)hostVersion comparator:(id<SUVersionComparison>)comparator
{
    SUAppcastItem *item = nil;
    for(SUAppcastItem *candidate in appcastItems) {
        if (!item || [comparator compareVersion:item.versionString toVersion:candidate.versionString] == NSOrderedAscending) {
            item = candidate;
        }
    }
    
    if (item && deltaItem) {
        SUAppcastItem *deltaUpdateItem = [item deltaUpdates][hostVersion];
        if (deltaUpdateItem) {
            *deltaItem = deltaUpdateItem;
        }
    }
    
    return item;
}

+ (BOOL)itemOperatingSystemIsOK:(SUAppcastItem *)ui
{
    BOOL osOK = [ui isMacOsUpdate];
    if (([ui minimumSystemVersion] == nil || [[ui minimumSystemVersion] isEqualToString:@""]) &&
        ([ui maximumSystemVersion] == nil || [[ui maximumSystemVersion] isEqualToString:@""])) {
        return osOK;
    }
    
    BOOL minimumVersionOK = YES;
    BOOL maximumVersionOK = YES;
    
    // We don't want to use delegate's comparator for comparing OS versions
    id<SUVersionComparison> versionComparator = [[SUStandardVersionComparator alloc] init];
    
    // Check minimum and maximum System Version
    if ([ui minimumSystemVersion] != nil && ![[ui minimumSystemVersion] isEqualToString:@""]) {
        minimumVersionOK = [versionComparator compareVersion:[ui minimumSystemVersion] toVersion:[SUOperatingSystem systemVersionString]] != NSOrderedDescending;
    }
    if ([ui maximumSystemVersion] != nil && ![[ui maximumSystemVersion] isEqualToString:@""]) {
        maximumVersionOK = [versionComparator compareVersion:[ui maximumSystemVersion] toVersion:[SUOperatingSystem systemVersionString]] != NSOrderedAscending;
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
    return [[self versionComparator] compareVersion:[self.host version] toVersion:[ui versionString]] == NSOrderedAscending;
}

- (BOOL)itemPreventsAutoupdate:(SUAppcastItem *)ui
 {
     return ([ui minimumAutoupdateVersion] && ! [[ui minimumAutoupdateVersion] isEqualToString:@""] && ([[self versionComparator] compareVersion:[self.host version] toVersion:[ui minimumAutoupdateVersion]] == NSOrderedAscending));
 }

- (BOOL)itemContainsSkippedVersion:(SUAppcastItem *)ui
{
    NSString *skippedVersion = [self.host objectForUserDefaultsKey:SUSkippedVersionKey];
    if (skippedVersion == nil) { return NO; }
    return [[self versionComparator] compareVersion:[ui versionString] toVersion:skippedVersion] != NSOrderedDescending;
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

@end
