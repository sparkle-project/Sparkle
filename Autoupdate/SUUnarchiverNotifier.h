//
//  SUUnarchiverNotifier.h
//  Sparkle
//
//  Created by Mayur Pawashe on 12/21/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SUUnarchiverNotifier : NSObject

- (instancetype)initWithCompletionBlock:(void (^)(NSError * _Nullable))completionBlock progressBlock:(void (^ _Nullable)(double))progressBlock __attribute__((objc_direct));

- (void)notifySuccess __attribute__((objc_direct));

- (void)notifyFailureWithError:(NSError * _Nullable)reason __attribute__((objc_direct));

- (void)notifyProgress:(double)progress __attribute__((objc_direct));

@end

NS_ASSUME_NONNULL_END
