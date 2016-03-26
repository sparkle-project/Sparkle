//
//  SUSecureCoding.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/24/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

NSData *SUArchiveRootObjectSecurely(id<NSSecureCoding> rootObject);

id<NSSecureCoding> _Nullable SUUnarchiveRootObjectSecurely(NSData *data, Class klass);

NS_ASSUME_NONNULL_END
