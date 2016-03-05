//
//  TestAppHelperProtocol.h
//  TestAppHelper
//
//  Created by Mayur Pawashe on 3/2/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

// The protocol that this service will vend as its API. This header file will also need to be visible to the process hosting the service.
@protocol TestAppHelperProtocol

- (void)codeSignApplicationAtPath:(NSString *)applicationPath reply:(void (^)(BOOL))reply;

// Start up Sparkle
- (void)startSparkle;

// Check for updates when the user wants to check for them explicitly
- (void)initiateUserCheckForUpdates;

// Check for updates, only bringing a prompt when an update is available and not skipped
- (void)checkForUpdates;

- (void)retrieveUpdateSettings:(void (^)(BOOL automaticallyCheckForUpdates, BOOL automaticallyDownloadUpdates, BOOL sendSystemProfile, NSTimeInterval updateCheckInterval))reply;

- (void)setAutomaticallyChecksForUpdates:(BOOL)automaticallyChecksForUpdates;
- (void)setAutomaticallyDownloadsUpdates:(BOOL)automaticallyDownloadsUpdates;
- (void)setSendsSystemProfile:(BOOL)sendsSystemProfile;
- (void)setUpdateCheckInterval:(NSTimeInterval)updateCheckInterval;

@end

/*
 To use the service from an application or other process, use NSXPCConnection to establish a connection to the service by doing something like this:

     _connectionToService = [[NSXPCConnection alloc] initWithServiceName:@"org.sparkle-project.TestAppHelper"];
     _connectionToService.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(StringModifing)];
     [_connectionToService resume];

Once you have a connection to the service, you can use it like this:

     [[_connectionToService remoteObjectProxy] upperCaseString:@"hello" withReply:^(NSString *aString) {
         // We have received a response. Update our text field, but do it on the main thread.
         NSLog(@"Result string was: %@", aString);
     }];

 And, when you are finished with the service, clean up the connection like this:

     [_connectionToService invalidate];
*/
