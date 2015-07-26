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
#include <xar/xar.h>

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

NSString *stringWithFileSystemRepresentation(const char *input) {
    NSFileManager *fm = [NSFileManager defaultManager];
    return [fm stringWithFileSystemRepresentation:input length:strlen(input)];
}

NSString *temporaryFilename(NSString *base)
{
    NSString *template = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.XXXXXXXXXX", base]];
    const char *fsrepr = [template fileSystemRepresentation];

    const size_t buffer_len = strlen(fsrepr) + 1;
    char *buffer = (char *)malloc(buffer_len);
    strlcpy(buffer, fsrepr, buffer_len);

    // mkstemp() can't be used, beause it returns a file descriptor, and XAR API requires a filename
    NSString *ret = stringWithFileSystemRepresentation(mktemp(buffer));
    free(buffer);
    return ret;
}

static void _hashOfBuffer(unsigned char *hash, const char* buffer, ssize_t bufferLength)
{
    assert(bufferLength >= 0 && bufferLength <= UINT32_MAX);
    CC_SHA1_CTX hashContext;
    CC_SHA1_Init(&hashContext);
    CC_SHA1_Update(&hashContext, buffer, (CC_LONG)bufferLength);
    CC_SHA1_Final(hash, &hashContext);
}

static void _hashOfFile(unsigned char* hash, FTSENT *ent)
{
    if (ent->fts_info == FTS_SL) {
        char linkDestination[MAXPATHLEN + 1];
        ssize_t linkDestinationLength = readlink(ent->fts_path, linkDestination, MAXPATHLEN);
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

        ssize_t fileSize = ent->fts_statp->st_size;
        if (fileSize == 0) {
            _hashOfBuffer(hash, NULL, 0);
            close(fileDescriptor);
            return;
        }

        void *buffer = mmap(0, (size_t)fileSize, PROT_READ, MAP_FILE | MAP_PRIVATE, fileDescriptor, 0);
        if (buffer == (void*)-1) {
            close(fileDescriptor);
            perror("mmap");
            return;
        }

        _hashOfBuffer(hash, buffer, fileSize);
        munmap(buffer, (size_t)fileSize);
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
    const char *sourcePaths[] = {[path fileSystemRepresentation], 0};
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

        NSString *relativePath = pathRelativeToDirectory(path, stringWithFileSystemRepresentation(ent->fts_path));
        const char *relativePathBytes = [relativePath fileSystemRepresentation];
        CC_SHA1_Update(&hashContext, relativePathBytes, (CC_LONG)strlen(relativePathBytes));
    }
    fts_close(fts);

    unsigned char hash[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1_Final(hash, &hashContext);

    char hexHash[CC_SHA1_DIGEST_LENGTH * 2 + 1];
    size_t i;
    for (i = 0; i < CC_SHA1_DIGEST_LENGTH; i++)
        sprintf(hexHash + i * 2, "%02x", hash[i]);

    return @(hexHash);
}

void removeTree(NSString *path)
{
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}

void copyTree(NSString *source, NSString *dest)
{
    [[NSFileManager defaultManager] copyItemAtPath:source toPath:dest error:nil];
}
