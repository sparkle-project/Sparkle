//
//  SUApplicationInfo.h
//  Sparkle
//
//  Created by Mayur Pawashe on 2/28/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPUApplicationInfo : NSObject

+ (BOOL)isBackgroundApplication:(NSApplication *)application;

+ (NSImage *)bestIconForBundle:(NSBundle *)bundle;

+ (NSRunningApplication * _Nullable)runningApplicationWithBundle:(NSBundle *)bundle;

@end

NS_ASSUME_NONNULL_END
