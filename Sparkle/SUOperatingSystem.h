//
//  SUOperatingSystem.h
//  Sparkle
//
//  Copyright © 2015 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface SUOperatingSystem : NSObject

+ (NSString *)systemVersionString __attribute__((objc_direct));

@end
