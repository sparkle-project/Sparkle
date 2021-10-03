//
//  SPUUserInitiatedUpdateDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUUserInitiatedUpdateDriver.h"
#import "SPUUIBasedUpdateDriver.h"
#import "SPUUserDriver.h"


#include "AppKitPrevention.h"

@interface SPUUserInitiatedUpdateDriver () <SPUUIBasedUpdateDriverDelegate>

@property (nonatomic, readonly) SPUUIBasedUpdateDriver *uiDriver;
@property (nonatomic, readonly) id<SPUUserDriver> userDriver;
@property (nonatomic) BOOL showingUserInitiatedProgress;
@property (nonatomic) BOOL showingUpdate;
@property (nonatomic) BOOL aborted;
@property (nonatomic) void (^updateDidShowHandler)(void);

@end

@implementation SPUUserInitiatedUpdateDriver

@synthesize uiDriver = _uiDriver;
@synthesize userDriver = _userDriver;
@synthesize showingUserInitiatedProgress = _showingUserInitiatedProgress;
@synthesize showingUpdate = _showingUpdate;
@synthesize aborted = _aborted;
@synthesize updateDidShowHandler = _updateDidShowHandler;

- (instancetype)initWithHost:(SUHost *)host applicationBundle:(NSBundle *)applicationBundle updater:(id)updater userDriver:(id <SPUUserDriver>)userDriver updaterDelegate:(nullable id <SPUUpdaterDelegate>)updaterDelegate
{
    self = [super init];
    if (self != nil) {
        _uiDriver = [[SPUUIBasedUpdateDriver alloc] initWithHost:host applicationBundle:applicationBundle updater:updater userDriver:userDriver userInitiated:YES updaterDelegate:updaterDelegate delegate:self];
        _userDriver = userDriver;
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
    self.showingUserInitiatedProgress = YES;
    
    if (self.updateDidShowHandler != nil) {
        self.updateDidShowHandler();
        self.updateDidShowHandler = nil;
    }
    
    [self.userDriver showUserInitiatedUpdateCheckWithCancellation:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.showingUserInitiatedProgress) {
                [self abortUpdate];
            }
        });
    }];
    
    [self.uiDriver checkForUpdatesAtAppcastURL:appcastURL withUserAgent:userAgent httpHeaders:httpHeaders inBackground:NO];
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
    // When a new update check has not been initiated and an update has been resumed,
    // update the driver to indicate we are showing an update to the user
    self.showingUpdate = YES;
    
    if (self.updateDidShowHandler != nil) {
        self.updateDidShowHandler();
        self.updateDidShowHandler = nil;
    }
}

- (void)basicDriverIsRequestingAbortUpdateWithError:(nullable NSError *)error
{
    [self abortUpdateWithError:error];
}

- (void)coreDriverIsRequestingAbortUpdateWithError:(nullable NSError *)error
{
    [self abortUpdateWithError:error];
}

- (void)uiDriverIsRequestingAbortUpdateWithError:(nullable NSError *)error
{
    [self abortUpdateWithError:error];
}

- (void)basicDriverDidFinishLoadingAppcast
{
    if (self.showingUserInitiatedProgress) {
        self.showingUserInitiatedProgress = NO;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        if ([self.userDriver respondsToSelector:@selector(dismissUserInitiatedUpdateCheck)]) {
            [self.userDriver dismissUserInitiatedUpdateCheck];
        }
#pragma clang diagnostic pop
    }
}

- (void)abortUpdate
{
    [self abortUpdateWithError:nil];
}

- (void)abortUpdateWithError:(nullable NSError *)error
{
    if (self.showingUserInitiatedProgress) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        if ([self.userDriver respondsToSelector:@selector(dismissUserInitiatedUpdateCheck)]) {
            [self.userDriver dismissUserInitiatedUpdateCheck];
        }
#pragma clang diagnostic pop
        self.showingUserInitiatedProgress = NO;
    }
    self.aborted = YES;
    [self.uiDriver abortUpdateWithError:error showErrorToUser:YES];
}

@end
