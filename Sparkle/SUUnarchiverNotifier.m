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

@interface SUUnarchiverNotifier ()

@property (nonatomic, readonly, copy) void (^completionBlock)(NSError * _Nullable);
@property (nonatomic, readonly, copy) void (^ _Nullable progressBlock)(double);

@end

@implementation SUUnarchiverNotifier

@synthesize completionBlock = _completionBlock;
@synthesize progressBlock = _progressBlock;

- (instancetype)initWithCompletionBlock:(void (^)(NSError * _Nullable))completionBlock progressBlock:(void (^ _Nullable)(double))progressBlock
{
    self = [super init];
    if (self != nil) {
        _completionBlock = [completionBlock copy];
        _progressBlock = [progressBlock copy];
    }
    return self;
}

- (void)notifySuccess
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.completionBlock(nil);
    });
}

- (void)notifyFailureWithError:(NSError * _Nullable)reason
{
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:SULocalizedString(@"An error occurred while extracting the archive. Please try again later.", nil) forKey:NSLocalizedDescriptionKey];
    if (reason) {
        [userInfo setObject:(NSError * _Nonnull)reason forKey:NSUnderlyingErrorKey];
    }
    
    NSError *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUUnarchivingError userInfo:userInfo];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self.completionBlock(error);
    });
}

- (void)notifyProgress:(double)progress
{
    if (self.progressBlock != nil) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.progressBlock(progress);
        });
    }
}

@end
