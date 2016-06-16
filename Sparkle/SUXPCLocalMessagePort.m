//
//  SUXPCLocalMessagePort.m
//  Sparkle
//
//  Created by Mayur Pawashe on 6/14/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUXPCLocalMessagePort.h"
#import "SULog.h"

@interface SUXPCLocalMessagePort ()

@property (nonatomic, readonly) NSXPCConnection *connection;
@property (nonatomic) id<SULocalMessagePortDelegate> delegate;
@property (nonatomic, copy) void (^invalidationHandler)(void);

@end

@implementation SUXPCLocalMessagePort

@synthesize connection = _connection;
@synthesize delegate = _delegate;
@synthesize invalidationHandler = _invalidationHandler;

- (instancetype)initWithDelegate:(id<SULocalMessagePortDelegate>)delegate
{
    self = [self init];
    if (self != nil) {
        _connection = [[NSXPCConnection alloc] initWithServiceName:@LOCAL_MESSAGE_PORT_BUNDLE_ID];
        _connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SULocalMessagePortProtocol)];
        
        __weak SUXPCLocalMessagePort *weakSelf = self;
        _connection.invalidationHandler = ^{
            [weakSelf invokeInvalidation];
        };
        
        _connection.interruptionHandler = ^{
            SULog(@"LocalMessagePort service interrupted");
            [weakSelf invokeInvalidation];
            [weakSelf.connection invalidate];
        };
        
        _delegate = delegate;
        
        _connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SULocalMessagePortDelegate)];
        _connection.exportedObject = _delegate;
        
        [_connection resume];
    }
    return self;
}

- (void)setServiceName:(NSString *)serviceName
{
    [self.connection.remoteObjectProxy setServiceName:serviceName];
}

- (void)invokeInvalidation
{
    if (self.invalidationHandler != nil) {
        self.invalidationHandler();
        self.invalidationHandler = nil;
    }
    self.delegate = nil;
}

- (void)setInvalidationCallback:(void (^)(void))invalidationCallback
{
    self.invalidationHandler = [invalidationCallback copy];
    
    __weak SUXPCLocalMessagePort *weakSelf = self;
    [self.connection.remoteObjectProxy setInvalidationCallback:^{
        [weakSelf invokeInvalidation];
    }];
}

- (void)invalidate
{
    [self.connection.remoteObjectProxy invalidate];
    [self.connection invalidate];
}

@end
