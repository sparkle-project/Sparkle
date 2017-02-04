//
//  SUNoOpUnarchiver.m
//  Sparkle
//
//  Created by Andoni Morales Alastruey on 4/2/17.
//  Copyright © 2017 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "SUNoOpUnarchiver.h"
#import "SUUnarchiverNotifier.h"
#import "SULog.h"
#import "SUErrors.h"

#include "AppKitPrevention.h"

@interface SUNoOpUnarchiver ()

@property (nonatomic, copy, readonly) NSString *archivePath;

@end

@implementation SUNoOpUnarchiver

@synthesize archivePath = _archivePath;

+ (BOOL)canUnarchivePath:(NSString *)path
{
    NSArray<NSString *> *extensionsArray = @[@".pkg", @".mpkg"];

    NSString *lastPathComponent = [path lastPathComponent];
    for (NSString *currentExtension in extensionsArray)
    {
        if ([lastPathComponent hasSuffix:currentExtension]) {
            return YES;
        }
    }
    return NO;
}

+ (BOOL)unsafeIfArchiveIsNotValidated
{
    return NO;
}

- (instancetype)initWithArchivePath:(NSString *)archivePath
{
    self = [super init];
    if (self != nil) {
        _archivePath = [archivePath copy];
    }
    return self;
}

- (void)unarchiveWithCompletionBlock:(void (^)(NSError * _Nullable))completionBlock progressBlock:(void (^ _Nullable)(double))progressBlock
{
    SUUnarchiverNotifier *notifier = [[SUUnarchiverNotifier alloc] initWithCompletionBlock:completionBlock progressBlock:progressBlock];
    [notifier notifySuccess];
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@>", [self class], self.archivePath]; }

@end
