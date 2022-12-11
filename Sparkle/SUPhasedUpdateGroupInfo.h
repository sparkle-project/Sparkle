//
//  SUPhasedUpdateGroupInfo.h
//  Sparkle
//
//  Created by Mayur Pawashe on 01/24/21.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SUHost;

@interface SUPhasedUpdateGroupInfo : NSObject

+ (NSUInteger)updateGroupForHost:(SUHost*)host __attribute__((objc_direct));
+ (NSNumber*)setNewUpdateGroupIdentifierForHost:(SUHost*)host __attribute__((objc_direct));

@end

NS_ASSUME_NONNULL_END
