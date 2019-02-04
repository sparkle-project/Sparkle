//
//  SUPKGUnarchiver.m
//  Sparkle
//
//  Created by Thomas Schmitt
//  Copyright 2013-2019 Thomas Schmitt. All rights reserved.
//

#import "SUPKGUnarchiver.h"
#import "SUUnarchiverNotifier.h"
#import "SULog.h"


@interface SUPKGUnarchiver ()

@property (nonatomic, copy, readonly) NSString *archivePath;

@end

@implementation SUPKGUnarchiver
@synthesize archivePath = _archivePath;


+ (BOOL)canUnarchivePath:(NSString *)path
{
	return [path.pathExtension isEqualToString:@"pkg"];
}

+ (BOOL)mustValidateBeforeExtraction
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
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        SUUnarchiverNotifier *notifier = [[SUUnarchiverNotifier alloc] initWithCompletionBlock:completionBlock progressBlock:progressBlock];
        [notifier notifySuccess];
    });
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%@ <%@>", [self class], self.archivePath];
}

@end
