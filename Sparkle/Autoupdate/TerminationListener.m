//
//  TerminationListener.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/7/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "TerminationListener.h"

@interface TerminationListener ()

@property (nonatomic, readonly) NSBundle *bundle;
@property (nonatomic) NSRunningApplication *listeningApplication;
@property (nonatomic, copy) void (^completionBlock)(void);

@end

@implementation TerminationListener

@synthesize bundle = _bundle;
@synthesize listeningApplication = _listeningApplication;
@synthesize completionBlock = _completionBlock;

- (instancetype)initWithBundle:(NSBundle *)bundle
{
    if (!(self = [super init])) {
        return nil;
    }
    
    _bundle = bundle;
    
    return self;
}

// Don't cache the running application instance because it can change later any number of times after initialization
// If for example, the user re-launches the application and we haven't started listening yet
- (NSRunningApplication *)runningApplication
{
    NSString *bundlePath = self.bundle.bundlePath;
    NSString *bundleIdentifier = self.bundle.bundleIdentifier;
    
    NSArray *runningApplications =
    (bundleIdentifier != nil) ?
    [NSRunningApplication runningApplicationsWithBundleIdentifier:bundleIdentifier] :
    [[NSWorkspace sharedWorkspace] runningApplications];
    
    for (NSRunningApplication *runningApplication in runningApplications) {
        // Comparing the URLs hasn't worked well for me in practice, so I'm comparing the file paths instead
        if ([runningApplication.bundleURL.path isEqualToString:bundlePath]) {
            return runningApplication;
        }
    }
    return nil;
}

- (BOOL)terminated
{
    NSRunningApplication *runningApplication = [self runningApplication];
    return (runningApplication == nil || runningApplication.isTerminated);
}

- (void)startListeningWithCompletion:(void (^)(void))completionBlock
{
    NSRunningApplication *runningApplication = [self runningApplication];
    if (runningApplication == nil || runningApplication.terminated) {
        completionBlock();
    } else {
        self.completionBlock = completionBlock;
        
        // We must strongly reference the listening application, so it doesn't deallocate while we have KVO observer to it
        self.listeningApplication = runningApplication;
        [self.listeningApplication addObserver:self forKeyPath:NSStringFromSelector(@selector(isTerminated)) options:NSKeyValueObservingOptionNew context:NULL];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)__unused change context:(void *)__unused context
{
    if (object == self.listeningApplication && [keyPath isEqualToString:NSStringFromSelector(@selector(isTerminated))]) {
        if (self.listeningApplication.terminated) {
            [self.listeningApplication removeObserver:self forKeyPath:keyPath];
            self.completionBlock();
            self.completionBlock = nil;
        }
    }
}

@end
