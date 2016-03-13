//
//  TerminationListener.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/7/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "TerminationListener.h"

@interface TerminationListener ()

@property (nonatomic, readonly) NSRunningApplication *runningApplication;
@property (nonatomic, copy) void (^completionBlock)(BOOL);

@end

@implementation TerminationListener

@synthesize runningApplication = _runningApplication;
@synthesize completionBlock = _completionBlock;

- (instancetype)initWithBundle:(NSBundle *)bundle
{
    if (!(self = [super init])) {
        return nil;
    }
    
    NSString *bundlePath = bundle.bundlePath;
    NSString *bundleIdentifier = bundle.bundleIdentifier;
    
    NSArray *runningApplications =
        (bundleIdentifier != nil) ?
        [NSRunningApplication runningApplicationsWithBundleIdentifier:bundleIdentifier] :
        [[NSWorkspace sharedWorkspace] runningApplications];
    
        for (NSRunningApplication *runningApplication in runningApplications) {
            // Comparing the URLs hasn't worked well for me in practice, so I'm comparing the file paths instead
            if ([runningApplication.bundleURL.path isEqualToString:bundlePath]) {
                _runningApplication = runningApplication;
                break;
            }
        }
    
    return self;
}

- (void)cleanupWithSuccess:(BOOL)success completion:(void (^)(BOOL))completionBlock
{
    completionBlock(success);
}

- (void)startListeningWithCompletion:(void (^)(BOOL))completionBlock
{
    BOOL alreadyTerminated = (self.runningApplication == nil || self.runningApplication.isTerminated);
    if (alreadyTerminated) {
        [self cleanupWithSuccess:YES completion:completionBlock];
    } else {
        self.completionBlock = completionBlock;
        [self.runningApplication addObserver:self forKeyPath:NSStringFromSelector(@selector(isTerminated)) options:NSKeyValueObservingOptionNew context:NULL];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)__unused change context:(void *)__unused context
{
    if (object == self.runningApplication && [keyPath isEqualToString:NSStringFromSelector(@selector(isTerminated))]) {
        if (self.runningApplication.isTerminated) {
            [self.runningApplication removeObserver:self forKeyPath:keyPath];
            [self cleanupWithSuccess:YES completion:self.completionBlock];
            self.completionBlock = nil;
        }
    }
}

@end
