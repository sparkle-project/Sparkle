//
//  AppInstaller.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/7/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUUnarchiverProtocol.h"

@interface AppInstaller : NSObject

- (instancetype)initWithHostBundleIdentifier:(NSString *)hostBundleIdentifier;

- (void)start;

- (void)cleanupAndExitWithStatus:(int)status __attribute__((noreturn));

@end
