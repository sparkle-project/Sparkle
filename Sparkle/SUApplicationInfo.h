//
//  SUApplicationInfo.h
//  Sparkle
//
//  Created by Mayur Pawashe on 2/28/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#if SPARKLE_BUILD_UI_BITS || !BUILDING_SPARKLE

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SUHost, NSImage, NSApplication;

@interface SUApplicationInfo : NSObject

+ (BOOL)isBackgroundApplication:(NSApplication *)application __attribute__((objc_direct));

+ (NSImage *)bestIconForHost:(SUHost *)host __attribute__((objc_direct));

@end

NS_ASSUME_NONNULL_END

#endif
