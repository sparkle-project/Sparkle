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

__attribute__((objc_direct_members)) @interface SUPhasedUpdateGroupInfo : NSObject

+ (NSUInteger)updateGroupForHost:(SUHost*)host;
+ (NSNumber*)setNewUpdateGroupIdentifierForHost:(SUHost*)host;

@end

NS_ASSUME_NONNULL_END
