//
//  NSFileManager+Aliases.h
//  Sparkle
//
//  Created by Andy Matuschak on 2/4/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface NSFileManager (Aliases)
- (BOOL)isAliasFolderAtPath:(NSString *)path;
@end
