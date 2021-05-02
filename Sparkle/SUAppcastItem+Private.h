//
//  SUAppcastItem+Private.h
//  Sparkle
//
//  Created by Mayur Pawashe on 4/30/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#ifndef SUAppcastItem_Private_h
#define SUAppcastItem_Private_h

#if __has_feature(modules)
#if __has_warning("-Watimport-in-framework-header")
#pragma clang diagnostic ignored "-Watimport-in-framework-header"
#endif
@import Foundation;
#else
#import <Foundation/Foundation.h>
#endif

@interface SUAppcastItem (Private)

// Initializes with data from a dictionary provided by the RSS class.
- (instancetype)initWithDictionary:(NSDictionary *)dict;
- (instancetype)initWithDictionary:(NSDictionary *)dict failureReason:(NSString **)error;
- (instancetype)initWithDictionary:(NSDictionary *)dict relativeToURL:(NSURL *)appcastURL failureReason:(NSString **)error;

@end

#endif /* SUAppcastItem_Private_h */
