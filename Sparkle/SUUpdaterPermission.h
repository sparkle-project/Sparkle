//
//  SUUpdaterPermission.h
//  Sparkle
//
//  Created by Mayur Pawashe on 4/1/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SUUpdaterPermission : NSObject

// Must be called from main queue
+ (void)testUpdateWritabilityAtPath:(NSString *)path completion:(void (^)(BOOL))completionHandler;

@end

NS_ASSUME_NONNULL_END
