//
//  InstallerProgressAppController.h
//  Sparkle
//
//  Created by Mayur Pawashe on 4/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@protocol InstallerProgressAppControllerDelegate;

@interface InstallerProgressAppController : NSObject <NSApplicationDelegate>

- (instancetype)initWithApplication:(NSApplication *)application arguments:(NSArray<NSString *> *)arguments delegate:(id<InstallerProgressAppControllerDelegate>)delegate;

- (void)run;

@end

NS_ASSUME_NONNULL_END
