//
//  SPUSecureCoding.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/24/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUSecureCoding.h"
#import "SULog.h"


#include "AppKitPrevention.h"

static NSString *SURootObjectArchiveKey = @"SURootObjectArchive";

NSData * _Nullable SPUArchiveRootObjectSecurely(id<NSSecureCoding> rootObject)
{
    if (@available(macOS 10.13, *)) {
        NSError *error = nil;
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:rootObject requiringSecureCoding:YES error:&error];
        if (data == nil) {
            SULog(SULogLevelError, @"Error while securely archiving object: %@", error);
        }
        return data;
    } else {
        NSMutableData *data = [NSMutableData data];
        
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        NSKeyedArchiver *keyedArchiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
#pragma clang diagnostic pop
        keyedArchiver.requiresSecureCoding = YES;
        
        @try {
            [keyedArchiver encodeObject:rootObject forKey:SURootObjectArchiveKey];
            [keyedArchiver finishEncoding];
            return [data copy];
        } @catch (NSException *exception) {
            SULog(SULogLevelError, @"Exception while securely archiving object: %@", exception);
            [keyedArchiver finishEncoding];
            return nil;
        }
    }
}

id<NSSecureCoding> _Nullable SPUUnarchiveRootObjectSecurely(NSData *data, Class klass)
{
    if (@available(macOS 10.13, *)) {
        NSError *error = nil;
        id<NSSecureCoding> rootObject = [NSKeyedUnarchiver unarchivedObjectOfClass:klass fromData:data error:&error];
        if (rootObject == nil) {
            SULog(SULogLevelError, @"Error while securely unarchiving object: %@", error);
        }
        return rootObject;
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
#pragma clang diagnostic pop
        unarchiver.requiresSecureCoding = YES;
        
        @try {
            id<NSSecureCoding> rootObject = [unarchiver decodeObjectOfClass:klass forKey:SURootObjectArchiveKey];
            [unarchiver finishDecoding];
            return rootObject;
        } @catch (NSException *exception) {
            SULog(SULogLevelError, @"Exception while securely unarchiving object: %@", exception);
            [unarchiver finishDecoding];
            return nil;
        }
    }
}
