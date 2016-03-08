//
//  TerminationListener.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/7/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface TerminationListener : NSObject

- (instancetype)initWithProcessIdentifier:(NSNumber *)processIdentifier;

- (void)startListeningWithCompletion:(void (^)(BOOL))completionBlock;

@end
