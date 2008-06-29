//
//  NSNumber+Units.h
//  Sparkle
//
//  Created by Jonas Witt on 5/18/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface NSNumber (JWUnits)

+ (NSString *)humanReadableSizeFromDouble:(double)value;

@end
