//
//  SUBundleIcon.h
//  Sparkle
//
//  Created by Mayur Pawashe on 7/24/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SUHost;

@interface SUBundleIcon : NSObject

+ (NSURL * _Nullable)iconURLForHost:(SUHost *)host;

@end

NS_ASSUME_NONNULL_END
