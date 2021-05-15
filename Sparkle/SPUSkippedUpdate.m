//
//  SPUSkippedUpdate.m
//  Sparkle
//
//  Created by Mayur Pawashe on 5/8/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#import "SPUSkippedUpdate.h"
#import "SUHost.h"
#import "SUConstants.h"
#import "SUAppcastItem.h"


#include "AppKitPrevention.h"

#define SKIPPED_UPDATE_TAG_SEPARATOR @";skip;"

@implementation SPUSkippedUpdate

@synthesize version = _version;
@synthesize minimumAutoupdateVersion = _minimumAutoupdateVersion;

- (instancetype)initWithVersion:(NSString *)version minimumAutoupdateVersion:(nullable NSString *)minimumAutoupdateVersion
{
    self = [super init];
    if (self != nil) {
        _version = [version copy];
        _minimumAutoupdateVersion = [minimumAutoupdateVersion copy];
    }
    return self;
}

+ (NSString *)encodeSkippedUpdate:(SPUSkippedUpdate *)skippedUpdate
{
    NSMutableArray<NSString *> *components = [NSMutableArray array];
    
    [components addObject:skippedUpdate.version];
    
    NSString *minimumAutoupdateVersion = skippedUpdate.minimumAutoupdateVersion;
    if (minimumAutoupdateVersion != nil) {
        [components addObject:minimumAutoupdateVersion];
    }
    
    // We encode the version and minimum autoupdate version in a human readable form with our own separator
    return [components componentsJoinedByString:SKIPPED_UPDATE_TAG_SEPARATOR];
}

+ (nullable instancetype)decodeSkippedUpdateFromString:(id)stringObject
{
    if (![(NSObject *)stringObject isKindOfClass:[NSString class]]) {
        return nil;
    }
    
    NSString *string = stringObject;
    
    NSArray<NSString *> *components = [string componentsSeparatedByString:SKIPPED_UPDATE_TAG_SEPARATOR];
    switch (components.count) {
        case 1:
            return [[self alloc] initWithVersion:components[0] minimumAutoupdateVersion:nil];
        case 2:
            return [[self alloc] initWithVersion:components[0] minimumAutoupdateVersion:components[1]];
        default:
            return nil;
    }
}

+ (NSArray<SPUSkippedUpdate *> *)skippedUpdatesForHost:(SUHost *)host
{
    id skippedVersions = [host objectForUserDefaultsKey:SUSkippedVersionKey];
    if ([(NSObject *)skippedVersions isKindOfClass:[NSString class]]) {
        // Handle legacy skipped version format with just a single skipped version
        SPUSkippedUpdate *skippedUpdate = [SPUSkippedUpdate decodeSkippedUpdateFromString:skippedVersions];
        
        return (skippedUpdate != nil) ? @[skippedUpdate] : @[];
    } else if ([(NSObject *)skippedVersions isKindOfClass:[NSArray class]]) {
        // Handle array of skipped updates
        NSMutableArray *skippedUpdates = [NSMutableArray array];
        for (id skippedUpdateObject in skippedVersions) {
            SPUSkippedUpdate *skippedUpdate = [SPUSkippedUpdate decodeSkippedUpdateFromString:skippedUpdateObject];
            
            if (skippedUpdate != nil) {
                [skippedUpdates addObject:skippedUpdate];
            }
        }
        return [skippedUpdates copy];
    } else {
        return @[];
    }
}

+ (void)clearSkippedUpdatesForHost:(SUHost *)host
{
    [host setObject:nil forUserDefaultsKey:SUSkippedVersionKey];
}

+ (BOOL)minimumAutoupdateVersion:(NSString * _Nullable)minimumAutoupdateVersion isEqual:(NSString * _Nullable)minimumAutoupdateVersion2
{
    // Both are not provided
    if (minimumAutoupdateVersion == nil && minimumAutoupdateVersion2 == nil) {
        return YES;
    }
    
    // One of them is not provided
    if (minimumAutoupdateVersion == nil || minimumAutoupdateVersion2 == nil) {
        return NO;
    }
    
    // Both are provided
    return [minimumAutoupdateVersion isEqualToString:(NSString * _Nonnull)minimumAutoupdateVersion2];
}

+ (void)skipUpdate:(SUAppcastItem *)updateItem host:(SUHost *)host
{
    NSArray<SPUSkippedUpdate *> *currentSkippedUpdates = [self skippedUpdatesForHost:host];
    NSMutableArray<NSString *> *newEncodedSkippedUpdates = [NSMutableArray array];
    
    NSString *updateItemMinimumAutoupdateVersion = updateItem.minimumAutoupdateVersion;
    
    for (SPUSkippedUpdate *skippedUpdate in currentSkippedUpdates) {
        NSString *skippedUpdateMinimumAutoupdateVersion = skippedUpdate.minimumAutoupdateVersion;
        
        if ([self minimumAutoupdateVersion:updateItemMinimumAutoupdateVersion isEqual:skippedUpdateMinimumAutoupdateVersion]) {
            // On same train, skip adding this old update
            // It will be replaced by the new skipped update we will be adding
            continue;
        }
        
        // Add everything else that is on a different train
        // We should only have an update per train in skipped updates we store/load
        [newEncodedSkippedUpdates addObject:[SPUSkippedUpdate encodeSkippedUpdate:skippedUpdate]];
    }
    
    // Always add the new skipped update
    SPUSkippedUpdate *newSkippedUpdate = [[SPUSkippedUpdate alloc] initWithVersion:updateItem.versionString minimumAutoupdateVersion:updateItemMinimumAutoupdateVersion];
    
    [newEncodedSkippedUpdates addObject:[SPUSkippedUpdate encodeSkippedUpdate:newSkippedUpdate]];
    
    [host setObject:[newEncodedSkippedUpdates copy] forUserDefaultsKey:SUSkippedVersionKey];
}

@end
