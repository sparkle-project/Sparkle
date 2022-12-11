//
//  SPUUserAgent+Private.h
//  Sparkle
//
//  Created by Mayur Pawashe on 11/12/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

#if defined(BUILDING_SPARKLE_TESTS)
#import "SUExport.h"
#else
#import <Sparkle/SUExport.h>
#endif

NS_ASSUME_NONNULL_BEGIN

@class SUHost;

SU_EXPORT NSString *SPUMakeUserAgentWithHost(SUHost *responsibleHost, NSString * _Nullable displayNameSuffix);

SU_EXPORT NSString *SPUMakeUserAgentWithBundle(NSBundle *responsibleBundle, NSString * _Nullable displayNameSuffix);

NS_ASSUME_NONNULL_END
