//
//  TerminationListener.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/7/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TerminationListener : NSObject

- (instancetype)initWithProcessIdentifier:(NSNumber * _Nullable)processIdentifier;

@property (nonatomic, readonly) BOOL terminated;

- (void)startListeningWithCompletion:(void (^)(BOOL))completionBlock;

@end

NS_ASSUME_NONNULL_END
