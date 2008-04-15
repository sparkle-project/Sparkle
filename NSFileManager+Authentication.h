//
//  NSFileManager+Authentication.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/9/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#ifndef NSFILEMANAGER_PLUS_AUTHENTICATION_H
#define NSFILEMANAGER_PLUS_AUTHENTICATION_H

@interface NSFileManager (SUAuthenticationAdditions)
- (BOOL)copyPathWithAuthentication:(NSString *)src overPath:(NSString *)dst error:(NSError **)error;
@end

#endif
