//
//  SUUpdaterQueue.m
//  Sparkle
//
//  Created by Dmytro Tretiakov on 7/31/14.
//
//

#import "SUUpdaterQueue.h"
#import "SUUpdater.h"
#import "SUUpdater_Private.h"
#import "SUConstants.h"
#import "SUBasicUpdateDriver.h"
#import "SUUserInitiatedUpdateDriver.h"

@interface SUDelegateProxy : NSProxy <SUPrivateUpdaterDelegate>

@property (nonatomic, assign) id realDelegate;
@property (nonatomic, assign) SUUpdaterQueue *updaterQueue;

@end

@implementation SUDelegateProxy

@synthesize realDelegate;
@synthesize updaterQueue;

+ (BOOL)shouldRedirectToUpdaterQueue:(SEL)aSelector
{
    if (nil == aSelector)
        return NO;
    
    static NSSet *sSelectorsToRedirect = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sSelectorsToRedirect = [[NSSet alloc] initWithObjects:
                                NSStringFromSelector(@selector(updaterWillStartUpdateProcess:)),
                                NSStringFromSelector(@selector(updaterDidEndUpdateProcess:)),
                                NSStringFromSelector(@selector(updaterMayCheckForUpdates:)),
                                NSStringFromSelector(@selector(updater:mayShowModalAlert:)),
                                nil];
    });
    
    return [sSelectorsToRedirect containsObject:NSStringFromSelector(aSelector)];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector
{
    NSMethodSignature *signature = [self.realDelegate methodSignatureForSelector:selector];
    if (!signature)
    {
        signature = [self.updaterQueue methodSignatureForSelector:selector];
    }
    if (!signature)
    {
        signature = [super methodSignatureForSelector:selector];
    }
    return signature;
}

- (BOOL)respondsToSelector:(SEL)aSelector
{
    BOOL result = NO;
    
    if ([SUDelegateProxy shouldRedirectToUpdaterQueue:aSelector])
    {
        result = YES;
    }
    else
    {
        result = [self.realDelegate respondsToSelector:aSelector];
    }
    
    return result;
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    if ([SUDelegateProxy shouldRedirectToUpdaterQueue:[anInvocation selector]])
    {
        [anInvocation invokeWithTarget:self.updaterQueue];
    }
    else if ([self.realDelegate respondsToSelector:anInvocation.selector])
    {
        [anInvocation invokeWithTarget:self.realDelegate];
    }
}

- (BOOL)isKindOfClass:(Class)aClass
{
    if (self.realDelegate)
        return [self.realDelegate isKindOfClass:aClass];
    return NO;
}

@end

#pragma mark -

@interface SUUpdaterQueue ()
{
    NSMutableArray *_updaters;
    NSMutableDictionary *_delegatesMap;
}

@property (atomic, retain) NSMutableArray *updaters;
@property (atomic, retain) NSMutableDictionary *delegatesMap;
@property (atomic, retain) SUUpdater *currentUpdater;
@property (atomic, assign) dispatch_semaphore_t currentUpdaterSema;
@property (nonatomic, retain) NSObject *semaphoreSynchronizer;
@property (atomic, assign) BOOL shouldContinueCheck;
@property (nonatomic, retain) NSMutableArray *resultUIDrivers;

@property (atomic, assign, getter=isProcessingUpdatersCheck) BOOL processingUpdatersCheck;

@end

@implementation SUUpdaterQueue

@synthesize updaters;
@synthesize delegatesMap;
@synthesize currentUpdater;
@synthesize currentUpdaterSema;
@synthesize semaphoreSynchronizer;
@synthesize shouldContinueCheck;
@synthesize resultUIDrivers;
@synthesize processingUpdatersCheck;

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        self.semaphoreSynchronizer = [[NSObject alloc] init];
        self.updaters = [NSMutableArray array];
        self.delegatesMap = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)dealloc
{
    for (SUUpdater *updater in [self.updaters copy])
    {
        [self removeUpdater:updater];
    }
    
    @synchronized (self.semaphoreSynchronizer)
    {
        if (!self.currentUpdater && self.currentUpdaterSema)
        {
            dispatch_release(self.currentUpdaterSema);
            self.currentUpdaterSema = nil;
        }
    }
}

#pragma mark -

- (void)observeValueForKeyPath:(NSString __unused *)keyPath ofObject:(id)object change:(NSDictionary __unused *)change context:(void __unused *)context
{
    if ([object isKindOfClass:[SUUpdater class]])
    {
        [self updateUpdaterDelegate:object];
    }
}

- (void)updateUpdaterDelegate:(SUUpdater *)updater
{
    if ([SUDelegateProxy class] == [updater.delegate class] && self == [(SUDelegateProxy *)updater.delegate updaterQueue])
    {
        return;
    }
    
    @synchronized (self.delegatesMap)
    {
        id realDelegate = updater.delegate;
        SUDelegateProxy *proxy = [SUDelegateProxy alloc];
        proxy.realDelegate = realDelegate;
        proxy.updaterQueue = self;
        updater.delegate = proxy;
        
        NSString *updaterKey = [self mapKeyForUpdater:updater];
        self.delegatesMap[updaterKey] = proxy;
    }
}

- (NSString *)mapKeyForUpdater:(SUUpdater *)updater
{
    return [NSString stringWithFormat:@"%p", updater];
}

- (id)realDelegateForUpdater:(SUUpdater *)updater
{
    if (nil == updater)
        return nil;
    
    id delegate = nil;
    @synchronized (self.delegatesMap)
    {
        NSString *updaterKey = [self mapKeyForUpdater:updater];
        delegate = self.delegatesMap[updaterKey];
    }
    
    return delegate;
}

#pragma mark -

- (void)addUpdater:(SUUpdater *)updater
{
    if (nil == updater)
        return;
    
    if ([updater updateInProgress])
    {
        NSLog(@"Could not add updater while it's in progress");
        return;
    }
    
    @synchronized (self.updaters)
    {
        if (![self.updaters containsObject:updater])
        {
            [self updateUpdaterDelegate:updater];
            [updater addObserver:self forKeyPath:@"delegate" options:NSKeyValueObservingOptionNew context:NULL];
            [self.updaters addObject:updater];
        }
    }
}

- (void)removeUpdater:(SUUpdater *)updater
{
    if (nil == updater)
        return;
    
    if (updater == self.currentUpdater && self.currentUpdaterSema)
    {
        NSLog(@"Could not remove updater while it's in progress.");
        return;
    }
    
    @synchronized (self.updaters)
    {
        if ([self.updaters containsObject:updater])
        {
            [updater removeObserver:self forKeyPath:@"delegate"];
            id realDelegate = nil;
            NSString *updaterKey = [self mapKeyForUpdater:updater];
            
            @synchronized (self.delegatesMap)
            {
                realDelegate = [self.delegatesMap[updaterKey] realDelegate];
                [self.delegatesMap removeObjectForKey:updaterKey];
            }
            
            [updater setDelegate:realDelegate];
            [self.updaters removeObject:updater];
        }
    }
}

- (BOOL)updateInProgress
{
    return self.processingUpdatersCheck;
}

#pragma mark -

- (void)performCheckForUpdates:(NSString *)selectorName
{
    if (self.isProcessingUpdatersCheck)
        return;
    
    self.processingUpdatersCheck = YES;
    
    NSUInteger index = 0;
    self.shouldContinueCheck = YES;
    self.resultUIDrivers = [NSMutableArray array];
    do
    {
        // in case if some of queued updaters is already in process
        if (self.currentUpdater && self.currentUpdaterSema)
        {
            dispatch_semaphore_wait(self.currentUpdaterSema, DISPATCH_TIME_FOREVER);
            @synchronized (self.semaphoreSynchronizer)
            {
                dispatch_release(self.currentUpdaterSema);
                self.currentUpdaterSema = nil;
            }
        }
        
        if (!self.shouldContinueCheck)
            break;
        
        @synchronized (self.updaters)
        {
            self.currentUpdater = index < self.updaters.count ? self.updaters[index] : nil;
            index++;
        }
        
        if (nil == self.currentUpdater)
            break;

        @synchronized (self.semaphoreSynchronizer)
        {
            if (nil == self.currentUpdaterSema)
                self.currentUpdaterSema = dispatch_semaphore_create(0);
        }
        [self.currentUpdater performSelectorOnMainThread:NSSelectorFromString(selectorName)
                                              withObject:nil
                                           waitUntilDone:YES];
    }
    while (YES);
    
    if (SUUpdateAbortDidNotFind == [self.resultUIDrivers.lastObject abortReason])
    {
        SUBasicUpdateDriver *driver = nil;
        if (self.resultUIDrivers.count > 1)
        {
            SUUpdater *mainUpdater = [SUUpdater sharedUpdater];
            driver = [[SUUserInitiatedUpdateDriver alloc] initWithUpdater:mainUpdater];
            driver.host = mainUpdater.host;
        }
        else
        {
            driver = self.resultUIDrivers.lastObject;
        }
        
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wselector"
        [driver performSelectorOnMainThread:@selector(didNotFindUpdate) withObject:nil waitUntilDone:YES];
#pragma clang diagnostic pop
    }
    self.resultUIDrivers = nil;
    
    self.processingUpdatersCheck = NO;
}

- (void)checkForUpdates
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wselector"
    [self performSelectorInBackground:@selector(performCheckForUpdates:)
                           withObject:NSStringFromSelector(@selector(checkForUpdates:))];
#pragma clang diagnostic pop
}

- (void)checkForUpdatesInBackground
{
    [self performSelectorInBackground:@selector(performCheckForUpdates:)
                           withObject:NSStringFromSelector(@selector(checkForUpdatesInBackground))];
}

#pragma mark -

- (void)updaterWillStartUpdateProcess:(SUUpdater *)updater
{
    if ((nil != updater && nil == self.currentUpdater) ||
        (self.currentUpdater == updater))
    {
        self.currentUpdater = updater;
        @synchronized (self.semaphoreSynchronizer)
        {
            if (nil == self.currentUpdaterSema)
                self.currentUpdaterSema = dispatch_semaphore_create(0);
        }
    }
}

- (void)updaterDidEndUpdateProcess:(SUUpdater *)updater
{
    if (self.currentUpdater == updater)
    {
        self.currentUpdater = nil;
        @synchronized (self.semaphoreSynchronizer)
        {
            if (self.currentUpdaterSema)
                dispatch_semaphore_signal(self.currentUpdaterSema);
        }
        
        SUBasicUpdateDriver *driver = updater.basicDriver;
        do
        {
            if (!driver.shouldShowUI)
                break;
            
            if (SUUpdateAbortGotError == driver.abortReason)
            {
                self.resultUIDrivers = nil;
                self.shouldContinueCheck = NO;
                break;
            }

            [self.resultUIDrivers addObject:driver];
        }
        while (NO);
    }
}

- (BOOL)updaterMayCheckForUpdates:(SUUpdater *)updater
{
    BOOL result = NO;
    if (updater != nil && updater == self.currentUpdater)
    {
        id realDelegate = ([SUDelegateProxy class] == [updater.delegate class]) ? [(SUDelegateProxy *)updater.delegate realDelegate] : updater.delegate;
        result = ![realDelegate respondsToSelector:_cmd] || [realDelegate updaterMayCheckForUpdates:updater];
    }

    return result;
}

- (BOOL)updater:(SUUpdater *)updater mayShowModalAlert:(NSAlert *)alertToShow
{
    BOOL result = YES;
    
    if (updater != nil && updater == self.currentUpdater && self.shouldContinueCheck)
    {
        if (SUUpdateAbortGotError != updater.basicDriver.abortReason)
            result = NO;
    }
    else
    {
        id realDelegate = ([SUDelegateProxy class] == [updater.delegate class]) ? [(SUDelegateProxy *)updater.delegate realDelegate] : updater.delegate;
        result = ![realDelegate respondsToSelector:_cmd] || [realDelegate updater:updater mayShowModalAlert:alertToShow];
    }
    
    return result;
}

@end
