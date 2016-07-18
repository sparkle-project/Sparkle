//
//  InstallerProgressLauncher.m
//  Sparkle
//
//  Created by Mayur Pawashe on 7/17/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "InstallerProgressLauncher.h"
#import "SUMessageTypes.h"
#import "SUInstallerProgressLauncherProtocol.h"
#import "SUSubmitInstaller.h"
#import "SULog.h"

#define REQUEST_AUTHORIZATION_TIMEOUT 7ull

@interface InstallerProgressLauncher () <NSXPCListenerDelegate>

@property (nonatomic) NSXPCListener *xpcListener;
@property (nonatomic) NSXPCConnection *activeConnection;
@property (nonatomic, readonly) NSBundle *hostBundle;
@property (nonatomic, copy, readonly) NSString *installerPath;
@property (nonatomic, readonly) BOOL allowsInteraction;
@property (nonatomic, weak) id<InstallerProgressLauncherDelegate> delegate;
@property (nonatomic) BOOL connected;

@end

@implementation InstallerProgressLauncher

@synthesize xpcListener = _xpcListener;
@synthesize activeConnection = _activeConnection;
@synthesize hostBundle = _hostBundle;
@synthesize installerPath = _installerPath;
@synthesize allowsInteraction = _allowsInteraction;
@synthesize delegate = _delegate;
@synthesize connected = _connected;

- (instancetype)initWithHostBundle:(NSBundle *)hostBundle installerPath:(NSString *)installerPath allowingInteraction:(BOOL)allowingInteraction delegate:(id<InstallerProgressLauncherDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        NSString *bundleIdentifier = hostBundle.bundleIdentifier;
        assert(bundleIdentifier != nil);
        
        _hostBundle = hostBundle;
        _installerPath = [installerPath copy];
        _allowsInteraction = allowingInteraction;
        _delegate = delegate;
        
        _xpcListener = [[NSXPCListener alloc] initWithMachServiceName:SUProgressAgentLauncherServiceNameForBundleIdentifier(bundleIdentifier)];
        _xpcListener.delegate = self;
    }
    return self;
}

- (void)startListener
{
    [self.xpcListener resume];
}

- (void)invalidate
{
    // Declare local variable for the delegate, so that if the delegate invokes -invalidate, we won't be in an infinite recursion
    id<InstallerProgressLauncherDelegate> delegate = self.delegate;
    self.delegate = nil;
    [delegate installerProgressLauncherDidInvalidate];
    
    [self.activeConnection invalidate];
    [self.xpcListener invalidate];
    
    self.activeConnection = nil;
    self.xpcListener = nil;
}

- (BOOL)listener:(NSXPCListener *)__unused listener shouldAcceptNewConnection:(NSXPCConnection *)connection
{
    if (self.activeConnection != nil) {
        SULog(@"Error: active connection for progress launcher already exists");
        [connection invalidate];
        return NO;
    }
    
    connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUInstallerProgressLauncherProtocol)];
    connection.exportedObject = self;
    
    self.activeConnection = connection;
    
    __weak InstallerProgressLauncher *weakSelf = self;
    connection.interruptionHandler = ^{
        [weakSelf.activeConnection invalidate];
    };
    
    connection.invalidationHandler = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            InstallerProgressLauncher *strongSelf = weakSelf;
            if (strongSelf != nil) {
                strongSelf.activeConnection = nil;
                [strongSelf invalidate];
            }
        });
    };
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(REQUEST_AUTHORIZATION_TIMEOUT * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SULog(@"Dispatch timeout invoked");
        if (!self.connected) {
            [self invalidate];
        }
    });
    
    [connection resume];
    
    return YES;
}

- (void)requestUserAuthorizationWithReply:(void (^)(SUAuthorizationReply))reply
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.connected = YES;
        
        SUAuthorizationReply submissionReply = [SUSubmitInstaller submitInstallerAtPath:self.installerPath withHostBundle:self.hostBundle allowingInteraction:self.allowsInteraction inSystemDomain:YES];
        
        if (submissionReply == SUAuthorizationReplyFailure) {
            SULog(@"Error: failed to submit installer in system domain");
        }
        
        reply(submissionReply);
        
        if (submissionReply == SUAuthorizationReplySuccess) {
            [self.delegate installerProgressLauncherDidSubmitJob];
        }
    });
}

- (void)connectionDidInitiateWithReply:(void (^)(void))acknowledgement
{
    acknowledgement();
}

@end
