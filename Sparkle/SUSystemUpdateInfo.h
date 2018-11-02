//
//  SUSystemUpdateInfo.h
//  Sparkle
//
//  Created by Mayur Pawashe on 12/23/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SUHost;

@interface SUSystemUpdateInfo : NSObject

+ (BOOL)systemAllowsAutomaticUpdatesForHost:(SUHost *)host;

@end

NS_ASSUME_NONNULL_END
