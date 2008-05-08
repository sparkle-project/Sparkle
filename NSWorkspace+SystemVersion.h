//
//  NSWorkspace+SystemVersion.h
//  Sparkle
//
//  Created by Andy Matuschak on 5/7/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#ifndef NSWORKSPACE_PLUS_SYSTEMVERSION_H
#define NSWORKSPACE_PLUS_SYSTEMVERSION_H

#import <Cocoa/Cocoa.h>

@interface NSWorkspace (SystemVersion)
+ (NSString *)systemVersionString;
@end

#endif
