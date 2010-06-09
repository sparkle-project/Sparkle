//
//  SUBinaryDeltaCommon.m
//  Sparkle
//
//  Created by Mark Rowe on 2009-06-01.
//  Copyright 2009 Mark Rowe. All rights reserved.
//

#include "SUBinaryDeltaCommon.h"
#include <CommonCrypto/CommonDigest.h>
#include <Foundation/Foundation.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/param.h>
#include <sys/stat.h>

extern int xar_close(void*) __attribute__((weak_import));
    
int binaryDeltaSupported(void)
{
    // OS X 10.4 didn't include libxar, so we link against it weakly.
    // This checks whether libxar is available at runtime.
    return xar_close != 0;
}

int compareFiles(const FTSENT **a, const FTSENT **b)
{
    return strcoll((*a)->fts_name, (*b)->fts_name);
}

NSString *pathRelativeToDirectory(NSString *directory, NSString *path)
{
    NSUInteger directoryLength = [directory length];
    if ([path hasPrefix:directory])
        return [path substringFromIndex:directoryLength];

    return path;
}

NSString *temporaryFilename(NSString *base)
{
    NSString *template = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.XXXXXXXXXX", base]];
    char buffer[MAXPATHLEN];
    strcpy(buffer, [template fileSystemRepresentation]);
    return [NSString stringWithUTF8String:mktemp(buffer)];
}

static void _hashOfBuffer(unsigned char *hash, const char* buffer, size_t bufferLength)
{
    assert(bufferLength <= UINT32_MAX);
    CC_SHA1_CTX hashContext;
    CC_SHA1_Init(&hashContext);
    CC_SHA1_Update(&hashContext, buffer, (CC_LONG)bufferLength);
    CC_SHA1_Final(hash, &hashContext);
}

static void _hashOfFile(unsigned char* hash, FTSENT *ent)
{
    if (ent->fts_info == FTS_SL) {
        char linkDestination[MAXPATHLEN + 1];
        size_t linkDestinationLength = readlink(ent->fts_path, linkDestination, MAXPATHLEN);
        if (linkDestinationLength < 0) {
            perror("readlink");
            return;
        }

        _hashOfBuffer(hash, linkDestination, linkDestinationLength);
        return;
    }

    if (ent->fts_info == FTS_F) {
        int fileDescriptor = open(ent->fts_path, O_RDONLY);
        if (fileDescriptor == -1) {
            perror("open");
            return;
        }

        size_t fileSize = (size_t)ent->fts_statp->st_size;
        void *buffer = mmap(0, fileSize, PROT_READ, MAP_FILE | MAP_PRIVATE, fileDescriptor, 0);
        if (buffer == (void*)-1) {
            close(fileDescriptor);
            perror("mmap");
            return;
        }

        _hashOfBuffer(hash, buffer, fileSize);
        munmap(buffer, fileSize);
        close(fileDescriptor);
        return;
    }

    if (ent->fts_info == FTS_D)
        memset(hash, 0xdd, CC_SHA1_DIGEST_LENGTH);
}

NSData *hashOfFile(FTSENT *ent)
{
    unsigned char fileHash[CC_SHA1_DIGEST_LENGTH];
    _hashOfFile(fileHash, ent);
    return [NSData dataWithBytes:fileHash length:CC_SHA1_DIGEST_LENGTH];
}

NSString *hashOfTree(NSString *path)
{
    const char *sourcePaths[] = {[path UTF8String], 0};
    FTS *fts = fts_open((char* const*)sourcePaths, FTS_PHYSICAL | FTS_NOCHDIR, compareFiles);
    if (!fts) {
        perror("fts_open");
        return nil;
    }

    CC_SHA1_CTX hashContext;
    CC_SHA1_Init(&hashContext);

    FTSENT *ent = 0;
    while ((ent = fts_read(fts))) {
        if (ent->fts_info != FTS_F && ent->fts_info != FTS_SL)
            continue;

        unsigned char fileHash[CC_SHA1_DIGEST_LENGTH];
        _hashOfFile(fileHash, ent);
        CC_SHA1_Update(&hashContext, fileHash, sizeof(fileHash));

        NSString *relativePath = pathRelativeToDirectory(path, [NSString stringWithUTF8String:ent->fts_path]);
        NSData *relativePathBytes = [relativePath dataUsingEncoding:NSUTF8StringEncoding];
        CC_SHA1_Update(&hashContext, [relativePathBytes bytes], (uint32_t)[relativePathBytes length]);
    }
    fts_close(fts);

    unsigned char hash[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1_Final(hash, &hashContext);

    char hexHash[CC_SHA1_DIGEST_LENGTH * 2 + 1];
    size_t i;
    for (i = 0; i < CC_SHA1_DIGEST_LENGTH; i++)
        sprintf(hexHash + i * 2, "%02x", hash[i]);

    return [NSString stringWithUTF8String:hexHash];
}

void removeTree(NSString *path)
{
#if MAC_OS_X_VERSION_MIN_REQUIRED > MAC_OS_X_VERSION_10_4
    [[NSFileManager defaultManager] removeItemAtPath:path error:0];
#else
    [[NSFileManager defaultManager] removeFileAtPath:path handler:nil];
#endif
}

void copyTree(NSString *source, NSString *dest)
{
#if MAC_OS_X_VERSION_MIN_REQUIRED > MAC_OS_X_VERSION_10_4
    [[NSFileManager defaultManager] copyItemAtPath:source toPath:dest error:0];
#else
    [[NSFileManager defaultManager] copyPath:source toPath:dest handler:nil];
#endif    
}
