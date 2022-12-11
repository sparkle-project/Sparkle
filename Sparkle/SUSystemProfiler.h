//
//  SUSystemProfiler.h
//  Sparkle
//
//  Created by Andy Matuschak on 12/22/07.
//  Copyright 2007 Andy Matuschak. All rights reserved.
//

#ifndef SUSYSTEMPROFILER_H
#define SUSYSTEMPROFILER_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SUHost;
@interface SUSystemProfiler : NSObject

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)systemProfileArrayForHost:(SUHost *)host __attribute__((objc_direct));

@end

NS_ASSUME_NONNULL_END
#endif
