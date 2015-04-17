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

#define PERMISSION_FLAGS (S_IRWXU | S_IRWXG | S_IRWXO | S_ISUID | S_ISGID | S_ISVTX)

#define IS_VALID_PERMISSIONS(mode) \
    (((mode & PERMISSION_FLAGS) == 0755) || ((mode & PERMISSION_FLAGS) == 0644))

#define MAJOR_VERSION_IS_AT_LEAST(actualMajor, expectedMajor) (actualMajor >= expectedMajor)
#define LATEST_MINOR_VERSION_FOR_MAJOR_VERSION(major) \
    (major == AZURE_MAJOR_VERSION ? AZURE_MINOR_VERSION : BEIGE_MINOR_VERSION)

// Each major version will be assigned a name of a color
// Changes that break backwards compatibility will have different major versions
// Changes that affect creating but not applying patches will have different minor versions

#define AZURE_MAJOR_VERSION 1
#define AZURE_MINOR_VERSION 0

#define BEIGE_MAJOR_VERSION 2
#define BEIGE_MINOR_VERSION 0

#define FIRST_DELTA_DIFF_MAJOR_VERSION 1
#define FIRST_DELTA_DIFF_MINOR_VERSION 0

#define LATEST_DELTA_DIFF_MAJOR_VERSION BEIGE_MAJOR_VERSION

@class NSString;
@class NSData;

extern int compareFiles(const FTSENT **a, const FTSENT **b);
extern NSData *hashOfFileContents(FTSENT *ent);
extern NSString *hashOfTreeWithVersion(NSString *path, uint16_t majorVersion);
extern NSString *hashOfTree(NSString *path);
extern BOOL removeTree(NSString *path);
extern BOOL copyTree(NSString *source, NSString *dest);
extern BOOL modifyPermissions(NSString *path, mode_t desiredPermissions);
extern NSString *pathRelativeToDirectory(NSString *directory, NSString *path);
NSString *temporaryFilename(NSString *base);
NSString *temporaryDirectory(NSString *base);
NSString *stringWithFileSystemRepresentation(const char*);
#endif
