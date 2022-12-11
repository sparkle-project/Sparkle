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

- (instancetype)initWithProcessIdentifier:(NSNumber * _Nullable)processIdentifier __attribute__((objc_direct));

@property (nonatomic, readonly, direct) BOOL terminated;

// If the process identifier provided was nil, then the completion block will invoke immediately with a YES success
- (void)startListeningWithCompletion:(void (^)(BOOL success))completionBlock __attribute__((objc_direct));

@end

NS_ASSUME_NONNULL_END
