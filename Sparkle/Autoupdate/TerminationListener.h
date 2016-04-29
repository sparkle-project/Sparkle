//
//  TerminationListener.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/7/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface TerminationListener : NSObject

- (instancetype)initWithBundle:(NSBundle *)bundle;

@property (nonatomic, readonly) BOOL terminated;

- (void)startListeningWithCompletion:(void (^)(void))completionBlock;

@end

NS_ASSUME_NONNULL_END
