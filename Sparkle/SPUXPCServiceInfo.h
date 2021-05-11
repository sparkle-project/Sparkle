//
//  SPUXPCServiceInfo.h
//  Sparkle
//
//  Created by Mayur Pawashe on 4/17/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

BOOL SPUXPCServiceExists(NSString *bundleName);

BOOL SPUXPCValidateServiceIfBundleExists(NSString *bundleName, NSBundle *sparkleBundle, NSError * __autoreleasing *error);

NSBundle * _Nullable SPUXPCServiceBundle(NSString *bundleName);

NS_ASSUME_NONNULL_END
