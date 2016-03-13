//
//  SUUpdateDriver.m
//  Sparkle
//
//  Created by Andy Matuschak on 5/7/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUUpdateDriver.h"
#import "SUHost.h"
#import "SULog.h"
#import "SUUserDriver.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

NSString *const SUUpdateDriverFinishedNotification = @"SUUpdateDriverFinished";

@interface SUUpdateDriver ()

@property (weak) id updater;
@property (copy) NSURL *appcastURL;
@property (getter=isInterruptible) BOOL interruptible;

@end

@implementation SUUpdateDriver

@synthesize updater;
@synthesize userDriver = _userDriver;
@synthesize updaterDelegate = _updaterDelegate;
@synthesize sparkleBundle = _sparkleBundle;
@synthesize host;
@synthesize interruptible;
@synthesize finished;
@synthesize appcastURL;
@synthesize automaticallyInstallUpdates;

// Note the updater type is intentionally left as 'id' instead of SUUpdater*
// We don't want to include a depedency to SUUpdater. The only reason we pass an updater is to pass it in
// when calling methods on its delegate. This is an unfortunate legacy design decision (i.e, these methods should have
// never taken an updater instance to begin with)
- (instancetype)initWithUpdater:(id)anUpdater updaterDelegate:(id<SUUpdaterDelegate>)updaterDelegate userDriver:(id<SUUserDriver>)userDriver host:(SUHost *)aHost sparkleBundle:(NSBundle *)sparkleBundle
{
    if ((self = [super init])) {
        self.updater = anUpdater;
        self.host = aHost;
        _userDriver = userDriver;
        _updaterDelegate = updaterDelegate;
        _sparkleBundle = sparkleBundle;
    }
    return self;
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@, %@>", [self class], [self.host bundlePath], [self.host installationPath]]; }

- (void)checkForUpdatesAtURL:(NSURL *)URL
{
    self.appcastURL = URL;
}

- (void)abortUpdate
{
    [self setValue:@YES forKey:@"finished"];
    [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdateDriverFinishedNotification object:self];
}

@end
