//
//  SUApplicationInfo.h
//  Sparkle
//
//  Created by Mayur Pawashe on 2/28/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface SUApplicationInfo : NSObject

+ (BOOL)isBackgroundApplication:(NSApplication * __nonnull)application;

+ (NSImage *__nonnull)bestIconForBundle:(NSBundle * __nonnull)bundle;

@end
