//
//  AppInstaller.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/7/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "SUUnarchiver.h"

@interface AppInstaller : NSObject <SUUnarchiverDelegate>

- (instancetype)initWithHostBundleIdentifier:(NSString *)hostBundleIdentifier;

- (void)start;

@end
