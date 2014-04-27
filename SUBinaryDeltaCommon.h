//
//  SUBinaryDeltaCommon.h
//  Sparkle
//
//  Created by Mark Rowe on 2009-06-01.
//  Copyright 2009 Mark Rowe. All rights reserved.
//

#ifndef SUBINARYDELTACOMMON_H
#define SUBINARYDELTACOMMON_H

#include <fts.h>

@class NSString;
@class NSData;

extern int binaryDeltaSupported(void);
extern int compareFiles(const FTSENT **a, const FTSENT **b);
extern NSData *hashOfFile(FTSENT *ent);
extern NSString *hashOfTree(NSString *path);
extern void removeTree(NSString *path);
extern void copyTree(NSString *source, NSString *dest);
extern NSString *pathRelativeToDirectory(NSString *directory, NSString *path);
NSString *temporaryFilename(NSString *base);
NSString *stringWithFileSystemRepresentation(const char*);
#endif
