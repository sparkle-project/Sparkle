//
//  NSFileManager+Authentication.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/9/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import "Sparkle.h"

@interface NSFileManager (SUAuthenticationAdditions)
- (BOOL)copyPath:(NSString *)src overPath:(NSString *)dst withAuthentication:(BOOL)useAuthentication;
@end
