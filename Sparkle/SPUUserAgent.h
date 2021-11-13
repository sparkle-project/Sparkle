//
//  SPUUserAgent.h
//  Sparkle
//
//  Created by Mayur Pawashe on 11/12/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SUHost;

NSString *SPUMakeUserAgentWithHost(SUHost *responsibleHost, NSString * _Nullable displayNameSuffix);

NSString *SPUMakeUserAgentWithBundle(NSBundle *responsibleBundle, NSString * _Nullable displayNameSuffix);

NS_ASSUME_NONNULL_END
