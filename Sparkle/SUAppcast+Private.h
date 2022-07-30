//
//  SUAppcast+Private.h
//  Sparkle
//
//  Created by Mayur Pawashe on 4/30/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SPUAppcastItemStateResolver;

@interface SUAppcast (Private)

- (nullable instancetype)initWithXMLData:(NSData *)xmlData relativeToURL:(NSURL * _Nullable)relativeURL stateResolver:(SPUAppcastItemStateResolver *)stateResolver error:(NSError * __autoreleasing *)error;

- (SUAppcast *)copyByFilteringItems:(BOOL (^)(SUAppcastItem *))filterBlock;

@end

NS_ASSUME_NONNULL_END
