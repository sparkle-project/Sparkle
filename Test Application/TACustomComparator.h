//
//  TACustomComparator.h
//  Sparkle
//
//  Created by Edward Rudd on 7/10/13.
//  Copyright (c) 2013 OutOfOrder.cc. All rights reserved.
//

#import "SUVersionComparisonProtocol.h"

@interface TACustomComparator : NSObject <SUVersionComparison>

- (NSComparisonResult)compareVersion:(NSString *)versionA toVersion:(NSString *)versionB;

@end
