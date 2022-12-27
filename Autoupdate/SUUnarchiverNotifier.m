//
//  SUUnarchiverNotifier.m
//  Sparkle
//
//  Created by Mayur Pawashe on 12/21/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUUnarchiverNotifier.h"
#import "SULocalizations.h"
#import "SUErrors.h"


#include "AppKitPrevention.h"

@implementation SUUnarchiverNotifier
{
    void (^_completionBlock)(NSError * _Nullable);
    void (^ _Nullable _progressBlock)(double);
}

- (instancetype)initWithCompletionBlock:(void (^)(NSError * _Nullable))completionBlock progressBlock:(void (^ _Nullable)(double))progressBlock
{
    self = [super init];
    if (self != nil) {
        _completionBlock = [completionBlock copy];
        _progressBlock = [progressBlock copy];
    } else {
        assert(false);
    }
    return self;
}

- (void)notifySuccess
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_completionBlock(nil);
    });
}

- (void)notifyFailureWithError:(NSError * _Nullable)reason
{
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:@"An error occurred while extracting the archive. Please try again later." forKey:NSLocalizedDescriptionKey];
    if (reason) {
        [userInfo setObject:(NSError * _Nonnull)reason forKey:NSUnderlyingErrorKey];
    }
    
    NSError *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUUnarchivingError userInfo:userInfo];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_completionBlock(error);
    });
}

- (void)notifyProgress:(double)progress
{
    if (_progressBlock != nil) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_progressBlock(progress);
        });
    }
}

@end
