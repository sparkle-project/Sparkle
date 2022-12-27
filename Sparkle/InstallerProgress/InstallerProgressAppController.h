//
//  InstallerProgressAppController.h
//  Sparkle
//
//  Created by Mayur Pawashe on 4/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@protocol InstallerProgressDelegate;

SPU_OBJC_DIRECT_MEMBERS @interface InstallerProgressAppController : NSObject <NSApplicationDelegate>

- (instancetype)initWithApplication:(NSApplication *)application arguments:(NSArray<NSString *> *)arguments delegate:(id<InstallerProgressDelegate>)delegate;

- (void)run;

- (void)cleanupAndExitWithStatus:(int)status error:(NSError * _Nullable)error __attribute__((noreturn));

@end

NS_ASSUME_NONNULL_END
