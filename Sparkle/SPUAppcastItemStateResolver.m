//
//  SPUAppcastItemStateResolver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 5/31/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#import "SPUAppcastItemStateResolver.h"
#import "SPUAppcastItemStateResolver+Private.h"
#import "SPUAppcastItemState.h"
#import "SUVersionComparisonProtocol.h"
#import "SUStandardVersionComparator.h"
#import "SUConstants.h"
#import "SUOperatingSystem.h"


#include "AppKitPrevention.h"

@implementation SPUAppcastItemStateResolver
{
    NSString *_hostVersion;
    id<SUVersionComparison> _applicationVersionComparator;
    SUStandardVersionComparator *_standardVersionComparator;
}

- (instancetype)initWithHostVersion:(NSString *)hostVersion applicationVersionComparator:(id<SUVersionComparison>)applicationVersionComparator standardVersionComparator:(SUStandardVersionComparator *)standardVersionComparator
{
    self = [super init];
    if (self != nil) {
        _hostVersion = [hostVersion copy];
        _applicationVersionComparator = applicationVersionComparator;
        _standardVersionComparator = standardVersionComparator;
    }
    return self;
}

- (BOOL)isMinimumOperatingSystemVersionOK:(NSString * _Nullable)minimumSystemVersion
{
    BOOL minimumVersionOK = YES;
    if (minimumSystemVersion != nil && ![minimumSystemVersion isEqualToString:@""]) {
        minimumVersionOK = [_standardVersionComparator compareVersion:(NSString * _Nonnull)minimumSystemVersion toVersion:[SUOperatingSystem systemVersionString]] != NSOrderedDescending;
    }
    return minimumVersionOK;
}

- (BOOL)isMaximumOperatingSystemVersionOK:(NSString * _Nullable)maximumSystemVersion
{
    BOOL maximumVersionOK = YES;
    if (maximumSystemVersion != nil && ![maximumSystemVersion isEqualToString:@""]) {
        maximumVersionOK = [_standardVersionComparator compareVersion:(NSString * _Nonnull)maximumSystemVersion toVersion:[SUOperatingSystem systemVersionString]] != NSOrderedAscending;
    }
    return maximumVersionOK;
}

+ (BOOL)isMinimumAutoupdateVersionOK:(NSString * _Nullable)minimumAutoupdateVersion hostVersion:(NSString *)hostVersion versionComparator:(id<SUVersionComparison>)versionComparator
 {
     return (minimumAutoupdateVersion.length == 0 || ([versionComparator compareVersion:hostVersion toVersion:(NSString * _Nonnull)minimumAutoupdateVersion] != NSOrderedAscending));
 }

- (BOOL)isMinimumAutoupdateVersionOK:(NSString * _Nullable)minimumAutoupdateVersion
 {
     return [[self class] isMinimumAutoupdateVersionOK:minimumAutoupdateVersion hostVersion:_hostVersion versionComparator:_applicationVersionComparator];
 }

- (BOOL)isCriticalUpdateWithCriticalUpdateDictionary:(NSDictionary * _Nullable)criticalUpdateDictionary
{
    // Check if any critical update info is provided
    if (criticalUpdateDictionary == nil) {
        return NO;
    }
    
    // If no critical version is supplied, then it is critical
    NSString *criticalVersion = criticalUpdateDictionary[SUAppcastAttributeVersion];
    if (criticalVersion == nil || ![criticalVersion isKindOfClass:[NSString class]]) {
        return YES;
    }
    
    // Update is only critical when coming from previous versions
    return ([_applicationVersionComparator compareVersion:_hostVersion toVersion:criticalVersion] == NSOrderedAscending);
}

- (BOOL)isInformationalUpdateWithInformationalUpdateVersions:(NSSet<NSString *> * _Nullable)informationalUpdateVersions
{
    if (informationalUpdateVersions == nil) {
        return NO;
    }
    
    // Informational only update regardless of version the app is updating from
    if (informationalUpdateVersions.count == 0) {
        return YES;
    }
    
    NSString *hostVersion = _hostVersion;
    
    // Informational update only for a set of host versions we're updating from
    if ([informationalUpdateVersions containsObject:hostVersion]) {
        return YES;
    }
    
    // If an informational update version has a '<' prefix, this is an informational update if
    // hostVersion < this info update version
    for (NSString *informationalUpdateVersion in informationalUpdateVersions) {
        if ([informationalUpdateVersion hasPrefix:@"<"] && [_applicationVersionComparator compareVersion:hostVersion toVersion:[informationalUpdateVersion substringFromIndex:1]] == NSOrderedAscending) {
            return YES;
        }
    }
    
    return NO;
}

- (SPUAppcastItemState *)resolveStateWithInformationalUpdateVersions:(NSSet<NSString *> * _Nullable)informationalUpdateVersions minimumOperatingSystemVersion:(NSString * _Nullable)minimumOperatingSystemVersion maximumOperatingSystemVersion:(NSString * _Nullable)maximumOperatingSystemVersion minimumAutoupdateVersion:(NSString * _Nullable)minimumAutoupdateVersion criticalUpdateDictionary:(NSDictionary * _Nullable)criticalUpdateDictionary
{
    BOOL informationalUpdate = [self isInformationalUpdateWithInformationalUpdateVersions:informationalUpdateVersions];
    
    BOOL minimumOperatingSystemVersionIsOK = [self isMinimumOperatingSystemVersionOK:minimumOperatingSystemVersion];
    
    BOOL maximumOperatingSystemVersionIsOK = [self isMaximumOperatingSystemVersionOK:maximumOperatingSystemVersion];;
    
    BOOL majorUpgrade = ![self isMinimumAutoupdateVersionOK:minimumAutoupdateVersion];
    
    BOOL criticalUpdate = [self isCriticalUpdateWithCriticalUpdateDictionary:criticalUpdateDictionary];
    
    return [[SPUAppcastItemState alloc] initWithMajorUpgrade:majorUpgrade criticalUpdate:criticalUpdate informationalUpdate:informationalUpdate minimumOperatingSystemVersionIsOK:minimumOperatingSystemVersionIsOK maximumOperatingSystemVersionIsOK:maximumOperatingSystemVersionIsOK];
}

@end
