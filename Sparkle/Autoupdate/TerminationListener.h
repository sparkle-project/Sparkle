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

- (void)startListeningWithCompletion:(void (^)(BOOL))completionBlock;

@end

NS_ASSUME_NONNULL_END
