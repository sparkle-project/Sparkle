//
//  NSURL+Parameters.h
//  Sparkle
//
//  Created by Andy Matuschak on 5/6/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#ifndef NSURL_PLUS_PARAMETERS_H
#define NSURL_PLUS_PARAMETERS_H

#import <Cocoa/Cocoa.h>

@interface NSURL (SUParameterAdditions)
- (NSURL *)URLWithParameters:(NSArray *)parameters;
@end

#endif
