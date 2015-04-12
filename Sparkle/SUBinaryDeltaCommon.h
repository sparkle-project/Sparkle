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

// Only track executable bits, which is what VCS's like git and hg do as well
// Other permission bits might be too sketchy to track
#define EXECUTABLE_PERMISSIONS (S_IXUSR | S_IXGRP | S_IXOTH)

#define DIFF_VERSION_IS_AT_LEAST(actualMajor, actualMinor, expectedMajor, expectedMinor) \
    ((actualMajor > expectedMajor) || (actualMajor == expectedMajor && actualMinor >= expectedMinor))

#define FIRST_DELTA_DIFF_MAJOR_VERSION 1
#define FIRST_DELTA_DIFF_MINOR_VERSION 0

#define LATEST_DELTA_DIFF_MAJOR_VERSION 1
#define LATEST_DELTA_DIFF_MAJOR_VERSION_STR _LATEST_DELTA_DIFF_VERSION_STR(LATEST_DELTA_DIFF_MAJOR_VERSION)

#define LATEST_DELTA_DIFF_MINOR_VERSION 1
#define LATEST_DELTA_DIFF_MINOR_VERSION_STR _LATEST_DELTA_DIFF_VERSION_STR(LATEST_DELTA_DIFF_MINOR_VERSION)

// See https://gcc.gnu.org/onlinedocs/cpp/Stringification.html#Stringification
#define __LATEST_DELTA_DIFF_VERSION_STR(s) #s
#define _LATEST_DELTA_DIFF_VERSION_STR(s) __LATEST_DELTA_DIFF_VERSION_STR(s)

@class NSString;
@class NSData;

extern int compareFiles(const FTSENT **a, const FTSENT **b);
extern NSData *hashOfFileContents(FTSENT *ent);
extern NSString *hashOfTreeWithVersion(NSString *path, uint16_t majorVersion, uint16_t minorVersion);
extern NSString *hashOfTree(NSString *path);
extern BOOL removeTree(NSString *path);
extern BOOL copyTree(NSString *source, NSString *dest);
extern NSString *pathRelativeToDirectory(NSString *directory, NSString *path);
NSString *temporaryFilename(NSString *base);
NSString *temporaryDirectory(NSString *base);
NSString *stringWithFileSystemRepresentation(const char*);
#endif
