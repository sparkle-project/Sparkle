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

NSBundle * _Nullable SPUXPCServiceBundle(NSString *bundleName);

NS_ASSUME_NONNULL_END
