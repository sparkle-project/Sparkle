//
//  SUOperatingSystem.h
//  Sparkle
//
//  Copyright © 2015 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

__attribute__((objc_direct_members)) @interface SUOperatingSystem : NSObject

+ (NSString *)systemVersionString;

@end
