//
//  AgentConnection.h
//  Sparkle
//
//  Created by Mayur Pawashe on 7/17/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol AgentConnectionDelegate <NSObject>

- (void)agentConnectionDidInitiate;
- (void)agentConnectionDidInvalidate;

@end

@protocol SPUInstallerAgentProtocol;

@interface AgentConnection : NSObject

- (instancetype)initWithHostBundleIdentifier:(NSString *)bundleIdentifier delegate:(id<AgentConnectionDelegate>)delegate __attribute__((objc_direct));

- (void)startListener __attribute__((objc_direct));
- (void)invalidate __attribute__((objc_direct));

@property (nonatomic, readonly, nullable, direct) id<SPUInstallerAgentProtocol> agent;
@property (nonatomic, readonly, direct) BOOL connected;
@property (nonatomic, nullable, direct) NSError *invalidationError;

@end

NS_ASSUME_NONNULL_END
