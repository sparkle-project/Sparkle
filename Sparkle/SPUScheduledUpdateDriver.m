//
//  SPUScheduledUpdateDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/15/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUScheduledUpdateDriver.h"
#import "SUHost.h"
#import "SUErrors.h"
#import "SPUUpdaterDelegate.h"
#import "SPUUserDriver.h"


#include "AppKitPrevention.h"

@interface SPUScheduledUpdateDriver() <SPUUIBasedUpdateDriverDelegate>

@property (nonatomic, readonly) SPUUIBasedUpdateDriver *uiDriver;
@property (nonatomic) BOOL showedUpdate;
@property (nonatomic) void (^updateDidShowHandler)(void);

@end

@implementation SPUScheduledUpdateDriver

@synthesize uiDriver = _uiDriver;
@synthesize showedUpdate = _showedUpdate;
@synthesize updateDidShowHandler = _updateDidShowHandler;

- (instancetype)initWithHost:(SUHost *)host applicationBundle:(NSBundle *)applicationBundle updater:(id)updater userDriver:(id <SPUUserDriver>)userDriver updaterDelegate:(nullable id <SPUUpdaterDelegate>)updaterDelegate
{
    self = [super init];
    if (self != nil) {
        _uiDriver = [[SPUUIBasedUpdateDriver alloc] initWithHost:host applicationBundle:applicationBundle updater:updater userDriver:userDriver userInitiated:NO updaterDelegate:updaterDelegate delegate:self];
    }
    return self;
}

- (void)setCompletionHandler:(SPUUpdateDriverCompletion)completionBlock
{
    [self.uiDriver setCompletionHandler:completionBlock];
}

- (void)setUpdateShownHandler:(void (^)(void))handler
{
    self.updateDidShowHandler = handler;
}

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary * _Nullable)httpHeaders
{
    [self.uiDriver checkForUpdatesAtAppcastURL:appcastURL withUserAgent:userAgent httpHeaders:httpHeaders inBackground:YES];
}

- (void)resumeInstallingUpdate
{
    [self.uiDriver resumeInstallingUpdate];
}

- (void)resumeUpdate:(id<SPUResumableUpdate>)resumableUpdate
{
    [self.uiDriver resumeUpdate:resumableUpdate];
}

- (void)uiDriverDidShowUpdate
{
    self.showedUpdate = YES;
    
    if (self.updateDidShowHandler != nil) {
        self.updateDidShowHandler();
    }
}

- (BOOL)showingUpdate
{
    return self.showedUpdate;
}

- (void)basicDriverIsRequestingAbortUpdateWithError:(nullable NSError *) error
{
    [self abortUpdateWithError:error];
}

- (void)coreDriverIsRequestingAbortUpdateWithError:(nullable NSError *) error
{
    [self abortUpdateWithError:error];
}

- (void)uiDriverIsRequestingAbortUpdateWithError:(nullable NSError *)error
{
    [self abortUpdateWithError:error];
}

- (void)abortUpdate
{
    [self abortUpdateWithError:nil];
}

- (void)abortUpdateWithError:(nullable NSError *)error
{
    [self.uiDriver abortUpdateWithError:error showErrorToUser:self.showedUpdate];
}

@end
