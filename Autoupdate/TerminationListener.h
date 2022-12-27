//
//  TerminationListener.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/7/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

SPU_OBJC_DIRECT_MEMBERS @interface TerminationListener : NSObject

- (instancetype)initWithProcessIdentifier:(NSNumber * _Nullable)processIdentifier;

@property (nonatomic, readonly) BOOL terminated;

// If the process identifier provided was nil, then the completion block will invoke immediately with a YES success
- (void)startListeningWithCompletion:(void (^)(BOOL success))completionBlock;

@end

NS_ASSUME_NONNULL_END
