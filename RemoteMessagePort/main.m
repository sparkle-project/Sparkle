//
//  main.m
//  RemoteMessagePort
//
//  Created by Mayur Pawashe on 4/3/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SURemoteMessagePort.h"

@interface ServiceDelegate : NSObject <NSXPCListenerDelegate>
@end

@implementation ServiceDelegate

- (BOOL)listener:(NSXPCListener *)__unused listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection {
    // This method is where the NSXPCListener configures, accepts, and resumes a new incoming NSXPCConnection.
    
    // Configure the connection.
    newConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SURemoteMessagePortProtocol)];
    
    newConnection.exportedObject = [[SURemoteMessagePort alloc] init];
    
    // Resuming the connection allows the system to deliver more incoming messages.
    [newConnection resume];
    
    return YES;
}

@end

int main(int __unused argc, const char * __unused argv[])
{
    // Create the delegate for the service.
    ServiceDelegate *delegate = [ServiceDelegate new];
    
    // Set up the one NSXPCListener for this service. It will handle all incoming connections.
    NSXPCListener *listener = [NSXPCListener serviceListener];
    listener.delegate = delegate;
    
    // Resuming the serviceListener starts this service. This method does not return.
    [listener resume];
    return 0;
}
