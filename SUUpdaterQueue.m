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
#import "SUUserInitiatedUpdateDriver.h"

@interface SUDelegateProxy : NSProxy

@property (nonatomic, assign) id realDelegate;
@property (nonatomic, assign) SUUpdaterQueue *updaterQueue;

@end

@implementation SUDelegateProxy

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
        signature = [self methodSignatureForSelector:selector];
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

@property (readonly) NSMutableArray *updaters;
@property (readonly) NSMutableDictionary *delegatesMap;
@property (retain) SUUpdater *currentUpdater;
@property (assign) BOOL currentUpdaterInProcess;
@property (assign) BOOL shouldContinueCheck;
@property (nonatomic, retain) NSMutableArray *resultUIDrivers;

@end

@implementation SUUpdaterQueue

- (void)dealloc
{
    for (SUUpdater *updater in self.updaters)
    {
        [self removeUpdater:updater];
    }
    [_updaters release];
    [_delegatesMap release];
    self.currentUpdater = nil;
    self.resultUIDrivers = nil;
    
    [super dealloc];
}

- (NSMutableArray *)updaters
{
    if (nil == _updaters)
    {
        @synchronized (self)
        {
            _updaters = _updaters ? : [[NSMutableArray alloc] init];
        }
    }
    
    return [[_updaters retain] autorelease];
}

- (NSMutableDictionary *)delegatesMap
{
    if (nil == _delegatesMap)
    {
        @synchronized (self)
        {
            _delegatesMap = _delegatesMap ? : [[NSMutableDictionary alloc] init];
        }
    }
    
    return [[_delegatesMap retain] autorelease];
}

#pragma mark -

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([object isKindOfClass:[SUUpdater class]])
    {
        [self updateUpdaterDelegate:object];
    }
}

- (void)updateUpdaterDelegate:(SUUpdater *)updater
{
    if ([SUDelegateProxy class] == [[updater delegate] class] &&
        self == [[updater delegate] updaterQueue])
    {
        return;
    }
    
    @synchronized (self.delegatesMap)
    {
        id realDelegate = [updater delegate];
        SUDelegateProxy *proxy = [[SUDelegateProxy alloc] autorelease];
        proxy.realDelegate = realDelegate;
        proxy.updaterQueue = self;
        [updater setDelegate:proxy];
        
        NSString *updaterKey = [self mapKeyForUpdater:updater];
        [self.delegatesMap setObject:proxy forKey:updaterKey];
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
        delegate = [self.delegatesMap objectForKey:[self mapKeyForUpdater:updater]];
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
    
    NSMutableArray *updaters = self.updaters;
    @synchronized (updaters)
    {
        if (![updaters containsObject:updater])
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
    
    if (updater == self.currentUpdater && self.currentUpdaterInProcess)
    {
        NSLog(@"Could not remove updater while it's in progress.");
        return;
    }
    
    NSMutableArray *updaters = self.updaters;
    @synchronized (updaters)
    {
        if ([updaters containsObject:updater])
        {
            [updater removeObserver:self forKeyPath:@"delegate"];
            id realDelegate = nil;
            NSString *updaterKey = [self mapKeyForUpdater:updater];
            
            @synchronized (self.delegatesMap)
            {
                realDelegate = [[self.delegatesMap objectForKey:updaterKey] realDelegate];
                [self.delegatesMap removeObjectForKey:updaterKey];
            }
            
            [updater setDelegate:realDelegate];
            [updaters removeObject:updater];
        }
    }
}

#pragma mark -

- (void)performCheckForUpdates:(NSString *)selectorName
{
    NSUInteger index = 0;
    self.shouldContinueCheck = YES;
    self.resultUIDrivers = [NSMutableArray array];
    do
    {
        // in case if some of queued updaters is already in process
        while (self.currentUpdaterInProcess)
        {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5f]];
        }
        
        if (!self.shouldContinueCheck)
            break;
        
        @synchronized (self.updaters)
        {
            self.currentUpdater = index < [self.updaters count] ? [self.updaters objectAtIndex:index] : nil;
            index++;
        }
        
        if (nil == self.currentUpdater)
            break;

        self.currentUpdaterInProcess = YES;
        [self.currentUpdater performSelectorOnMainThread:NSSelectorFromString(selectorName)
                                              withObject:nil
                                           waitUntilDone:YES];
    }
    while (YES);
    
    if (SUUpdateAbortDidNotFind == [[self.resultUIDrivers lastObject] abortReason])
    {
        SUBasicUpdateDriver *driver = nil;
        if ([self.resultUIDrivers count] > 1)
        {
            SUUpdater *mainUpdater = [SUUpdater sharedUpdater];
            driver = [[[SUUserInitiatedUpdateDriver alloc] initWithUpdater:mainUpdater] autorelease];
            [driver setHost:[mainUpdater host]];
        }
        else
        {
            driver = [self.resultUIDrivers lastObject];
        }
        
        [driver performSelectorOnMainThread:@selector(didNotFindUpdate) withObject:nil waitUntilDone:YES];
    }
    self.resultUIDrivers = nil;
}

- (void)checkForUpdates
{
    [self performSelectorInBackground:@selector(performCheckForUpdates:)
                           withObject:NSStringFromSelector(@selector(checkForUpdates:))];
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
        self.currentUpdaterInProcess = YES;
    }
}

- (void)updaterDidEndUpdateProcess:(SUUpdater *)updater
{
    if (self.currentUpdater == updater)
    {
        self.currentUpdater = nil;
        self.currentUpdaterInProcess = NO;
        
        SUBasicUpdateDriver *driver = [updater driver];
        do
        {
            if (![driver shouldShowUI])
                break;
            
            if (SUUpdateAbortGotError == [driver abortReason])
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
        id realDelegate = [SUDelegateProxy class] == [[updater delegate] class] ? [[updater delegate] realDelegate] : [updater delegate];
        result = ![realDelegate respondsToSelector:_cmd] || [realDelegate updaterMayCheckForUpdates:updater];
    }

    return result;
}

- (BOOL)updater:(SUUpdater *)updater mayShowModalAlert:(NSAlert *)alertToShow
{
    BOOL result = YES;
    
    if (updater != nil && updater == self.currentUpdater && self.shouldContinueCheck)
    {
        if (SUUpdateAbortGotError != [[updater driver] abortReason])
            result = NO;
    }
    else
    {
        id realDelegate = [SUDelegateProxy class] == [[updater delegate] class] ? [[updater delegate] realDelegate] : [updater delegate];
        result = ![realDelegate respondsToSelector:_cmd] || [realDelegate updater:updater mayShowModalAlert:alertToShow];
    }
    
    return result;
}

@end
