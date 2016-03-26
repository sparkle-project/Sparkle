//
//  SUSecureCoding.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/24/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUSecureCoding.h"

static NSString *SURootObjectArchiveKey = @"SURootObjectArchive";

NSData *SUArchiveRootObjectSecurely(id<NSSecureCoding> rootObject)
{
    NSMutableData *data = [NSMutableData data];
    NSKeyedArchiver *keyedArchiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
    keyedArchiver.requiresSecureCoding = YES;
    
    [keyedArchiver encodeObject:rootObject forKey:SURootObjectArchiveKey];
    [keyedArchiver finishEncoding];
    
    return [data copy];
}

id<NSSecureCoding> _Nullable SUUnarchiveRootObjectSecurely(NSData *data, Class klass)
{
    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
    unarchiver.requiresSecureCoding = YES;
    
    id<NSSecureCoding> rootObject = [unarchiver decodeObjectOfClass:klass forKey:SURootObjectArchiveKey];
    [unarchiver finishDecoding];
    
    return rootObject;
}
