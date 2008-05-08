//
//  NSFileManager+Aliases.h
//  Sparkle
//
//  Created by Andy Matuschak on 2/4/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#ifndef NSFILEMANAGER_PLUS_ALIASES_H
#define NSFILEMANAGER_PLUS_ALIASES_H

#import <Cocoa/Cocoa.h>

@interface NSFileManager (Aliases)
- (BOOL)isAliasFolderAtPath:(NSString *)path;
@end

#endif
