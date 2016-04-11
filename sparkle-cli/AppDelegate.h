//
//  AppDelegate.h
//  sparkle-cli
//
//  Created by Mayur Pawashe on 4/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface AppDelegate : NSObject <NSApplicationDelegate>

- (nullable instancetype)initWithBundlePath:(const char *)bundlePath;

@end

NS_ASSUME_NONNULL_END
