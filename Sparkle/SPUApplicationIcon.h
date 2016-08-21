//
//  SPUApplicationIcon.h
//  Sparkle
//
//  Created by Mayur Pawashe on 8/20/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPUApplicationIcon : NSObject

+ (NSImage *)bestIconForBundle:(NSBundle *)bundle;

@end

NS_ASSUME_NONNULL_END
