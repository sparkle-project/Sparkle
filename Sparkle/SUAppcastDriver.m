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
            [self appcastDidFinishLoading:appcast includesSkippedUpdates:includesSkippedUpdates];
        }
    }];
}

- (void)appcastDidFinishLoading:(SUAppcast *)ac includesSkippedUpdates:(BOOL)includesSkippedUpdates
{
    [self.delegate didFinishLoadingAppcast:ac];
    
    NSDictionary *userInfo = @{ SUUpdaterAppcastNotificationKey: ac };
    [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterDidFinishLoadingAppCastNotification object:self.updater userInfo:userInfo];
    
    SUAppcastItem *item = nil;
    SUAppcastItem *nonDeltaUpdateItem = nil;
    
    // Now we have to find the best valid update in the appcast.
    if ([self.updaterDelegate respondsToSelector:@selector(bestValidUpdateInAppcast:forUpdater:)])
    {
        item = [self.updaterDelegate bestValidUpdateInAppcast:ac forUpdater:(id _Nonnull)self.updater];
    }
    
    if (item != nil)
    {
        // Does the delegate want to handle it?
        if ([item isDeltaUpdate]) {
            nonDeltaUpdateItem = [self.updaterDelegate bestValidUpdateInAppcast:[ac copyWithoutDeltaUpdates] forUpdater:(id _Nonnull)self.updater];
        }
    }
    else // If not, we'll take care of it ourselves.
    {
        // Find the best supported update
        SUAppcastItem *deltaUpdateItem = nil;
        item = [[self class] bestItemFromAppcastItems:ac.items getDeltaItem:&deltaUpdateItem withHostVersion:self.host.version comparator:[self versionComparator]];
        
        if (item && deltaUpdateItem) {
            nonDeltaUpdateItem = item;
            item = deltaUpdateItem;
        }
    }
    
    if ([self itemContainsValidUpdate:item includesSkippedUpdates:includesSkippedUpdates]) {
        self.nonDeltaUpdateItem = nonDeltaUpdateItem;
        [self.delegate didFindValidUpdateWithAppcastItem:item];
    } else {
        [self.delegate didNotFindUpdate];
    }
}

+ (SUAppcastItem *)bestItemFromAppcastItems:(NSArray *)appcastItems getDeltaItem:(SUAppcastItem * __autoreleasing *)deltaItem withHostVersion:(NSString *)hostVersion comparator:(id<SUVersionComparison>)comparator
{
    SUAppcastItem *item = nil;
    for(SUAppcastItem *candidate in appcastItems) {
        if ([[self class] hostSupportsItem:candidate]) {
            if (!item || [comparator compareVersion:item.versionString toVersion:candidate.versionString] == NSOrderedAscending) {
                item = candidate;
            }
        }
    }
    
    if (item && deltaItem) {
        SUAppcastItem *deltaUpdateItem = [item deltaUpdates][hostVersion];
        if (deltaUpdateItem && [[self class] hostSupportsItem:deltaUpdateItem]) {
            *deltaItem = deltaUpdateItem;
        }
    }
    
    return item;
}

+ (BOOL)hostSupportsItem:(SUAppcastItem *)ui
{
    if (([ui minimumSystemVersion] == nil || [[ui minimumSystemVersion] isEqualToString:@""]) &&
        ([ui maximumSystemVersion] == nil || [[ui maximumSystemVersion] isEqualToString:@""])) { return YES; }
    
    BOOL minimumVersionOK = TRUE;
    BOOL maximumVersionOK = TRUE;
    
    id<SUVersionComparison> versionComparator = [[SUStandardVersionComparator alloc] init];
    
    // Check minimum and maximum System Version
    if ([ui minimumSystemVersion] != nil && ![[ui minimumSystemVersion] isEqualToString:@""]) {
        minimumVersionOK = [versionComparator compareVersion:[ui minimumSystemVersion] toVersion:[SUOperatingSystem systemVersionString]] != NSOrderedDescending;
    }
    if ([ui maximumSystemVersion] != nil && ![[ui maximumSystemVersion] isEqualToString:@""]) {
        maximumVersionOK = [versionComparator compareVersion:[ui maximumSystemVersion] toVersion:[SUOperatingSystem systemVersionString]] != NSOrderedAscending;
    }
    
    return minimumVersionOK && maximumVersionOK;
}

- (id<SUVersionComparison>)versionComparator
{
    id<SUVersionComparison> comparator = nil;
    
    // Give the delegate a chance to provide a custom version comparator
    if ([self.updaterDelegate respondsToSelector:@selector(versionComparatorForUpdater:)]) {
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

- (BOOL)itemContainsSkippedVersion:(SUAppcastItem *)ui
{
    NSString *skippedVersion = [self.host objectForUserDefaultsKey:SUSkippedVersionKey];
    if (skippedVersion == nil) { return NO; }
    return [[self versionComparator] compareVersion:[ui versionString] toVersion:skippedVersion] != NSOrderedDescending;
}

- (BOOL)itemContainsValidUpdate:(SUAppcastItem *)ui includesSkippedUpdates:(BOOL)includesSkippedUpdates
{
    return ui && [[self class] hostSupportsItem:ui] && [self isItemNewer:ui] && (includesSkippedUpdates || ![self itemContainsSkippedVersion:ui]);
}

@end
