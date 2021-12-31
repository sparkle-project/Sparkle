//
//  SPUSparkleDeltaArchive.m
//  Sparkle
//
//  Created by Mayur Pawashe on 12/30/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#import "SPUSparkleDeltaArchive.h"
#import <bzlib.h>
#import <sys/stat.h>
#import <CommonCrypto/CommonDigest.h>
#import "SUBinaryDeltaCommon.h"


#include "AppKitPrevention.h"

#define SPARKLE_DELTA_FORMAT_MAGIC "spk!"
#define PARTIAL_IO_CHUNK_SIZE 16384 // this must be >= PATH_MAX

@interface SPUSparkleDeltaArchive ()

@property (nonatomic) FILE *file;
@property (nonatomic) BZFILE *bzipFile;
@property (nonatomic, readonly) SPUDeltaCompressionMode compression;
@property (nonatomic) BOOL errorDetected;
@property (nonatomic, readonly) BOOL writeMode;

@property (nonatomic) NSMutableArray<SPUDeltaArchiveItem *> *writableItems;

@end

@implementation SPUSparkleDeltaArchive

@synthesize file = _file;
@synthesize bzipFile = _bzipFile;
@synthesize compression = _compression;
@synthesize errorDetected = _errorDetected;
@synthesize writeMode = _writeMode;
@synthesize writableItems = _writableItems;

+ (BOOL)maySupportSafeExtraction
{
    return YES;
}

- (nullable instancetype)initWithPatchFileForWriting:(NSString *)patchFile compression:(SPUDeltaCompressionMode)compression compressionLevel:(int32_t)compressionLevel
{
    self = [super init];
    if (self != nil) {
        FILE *file = fopen(patchFile.fileSystemRepresentation, "wb");
        if (file == NULL) {
            NSLog(@"Failed to open for writing binary");
            return nil;
        }
        
        char magic[] = SPARKLE_DELTA_FORMAT_MAGIC;
        if (fwrite(magic, sizeof(magic) - 1, 1, file) < 1) {
            NSLog(@"Failed to write magic");
            fclose(file);
            return nil;
        }
        
        if (fwrite(&compression, sizeof(compression), 1, file) < 1) {
            NSLog(@"Failed to write compression");
            fclose(file);
            return nil;
        }
        
        if (compression == SPUDeltaCompressionModeBzip2) {
            int bzerror = 0;
            // Compression level can be 1 - 9
            int blockSize100k = compressionLevel;
            
            BZFILE *bzipFile = BZ2_bzWriteOpen(&bzerror, file, blockSize100k, 0, 0);
            if (bzipFile == NULL) {
                NSLog(@"Failed to bz write open: %d", bzerror);
                fclose(file);
                return nil;
            }
            
            _bzipFile = bzipFile;
        }
        
        _file = file;
        _writableItems = [NSMutableArray array];
        _compression = compression;
        _writeMode = YES;
    }
    return self;
}

- (nullable instancetype)initWithPatchFileForReading:(NSString *)patchFile
{
    self = [super init];
    if (self != nil) {
        _file = fopen(patchFile.fileSystemRepresentation, "rb");
        if (_file == NULL) {
            return nil;
        }
        
        char magic[5] = {0};
        if (fread(magic, sizeof(magic) - 1, 1, _file) < 1) {
            fclose(_file);
            return nil;
        }
        
        if (strncmp(magic, SPARKLE_DELTA_FORMAT_MAGIC, sizeof(magic) - 1) != 0) {
            fclose(_file);
            return nil;
        }
        
        SPUDeltaCompressionMode compression = 0;
        if (fread(&compression, sizeof(compression), 1, _file) < 1) {
            fclose(_file);
            return nil;
        }
        
        switch (compression) {
            case SPUDeltaCompressionModeNone:
                break;
            case SPUDeltaCompressionModeBzip2: {
                int bzerror = 0;
                
                BZFILE *bzipFile = BZ2_bzReadOpen(&bzerror, _file, 0, 0, NULL, 0);
                if (bzipFile == NULL) {
                    fclose(_file);
                    return nil;
                }
                
                _bzipFile = bzipFile;
                
                break;
            }
            default:
                fclose(_file);
                return nil;
        }
        
        _compression = compression;
    }
    return self;
}

- (void)dealloc
{
    [self close];
}

- (void)close
{
    if (self.bzipFile != NULL) {
        if (self.writeMode) {
            int bzerror = 0;
            BZ2_bzWriteClose64(&bzerror, self.bzipFile, 0, NULL, NULL, NULL, NULL);
        } else {
            int bzerror = 0;
            BZ2_bzReadClose(&bzerror, self.bzipFile);
        }

        self.bzipFile = NULL;
    }
    
    if (self.file != NULL) {
        fclose(self.file);
        self.file = NULL;
    }
}

- (BOOL)_readBuffer:(void *)buffer length:(int32_t)length
{
    if (self.errorDetected) {
        return NO;
    }
    
    switch (self.compression) {
        case SPUDeltaCompressionModeNone: {
            if (fread(buffer, (size_t)length, 1, self.file) < 1) {
                self.errorDetected = YES;
                return NO;
            } else {
                return YES;
            }
        }
        case SPUDeltaCompressionModeBzip2: {
            int bzerror = 0;
            int bytesRead = BZ2_bzRead(&bzerror, self.bzipFile, buffer, length);
            
            switch (bzerror) {
                case BZ_OK:
                case BZ_STREAM_END:
                    if (bytesRead < length) {
                        self.errorDetected = YES;
                        return NO;
                    } else {
                        return YES;
                    }
                default:
                    self.errorDetected = YES;
                    return NO;
            }
        }
    }
}

- (nullable SPUDeltaArchiveHeader *)readHeader
{
    uint16_t majorVersion = 0;
    if (![self _readBuffer:&majorVersion length:sizeof(majorVersion)]) {
        return nil;
    }
    
    uint16_t minorVersion = 0;
    if (![self _readBuffer:&minorVersion length:sizeof(minorVersion)]) {
        return nil;
    }
    
    unsigned char beforeTreeHash[CC_SHA1_DIGEST_LENGTH] = {0};
    if (![self _readBuffer:beforeTreeHash length:sizeof(beforeTreeHash)]) {
        return nil;
    }
    
    unsigned char afterTreeHash[CC_SHA1_DIGEST_LENGTH] = {0};
    if (![self _readBuffer:afterTreeHash length:sizeof(afterTreeHash)]) {
        return nil;
    }
    
    return [[SPUDeltaArchiveHeader alloc] initWithMajorVersion:majorVersion minorVersion:minorVersion beforeTreeHash:beforeTreeHash afterTreeHash:afterTreeHash];
}

- (NSArray<NSString *> *)_readRelativeFilePaths
{
    if (self.errorDetected) {
        return nil;
    }
    
    uint64_t filePathSectionSize = 0;
    if (![self _readBuffer:&filePathSectionSize length:sizeof(filePathSectionSize)]) {
        return nil;
    }
    
    if (filePathSectionSize == 0) {
        // Nothing has actually changed if there are no entries
        return @[];
    }
    
    char *fileTableData = calloc(1, filePathSectionSize);
    if (fileTableData == NULL) {
        self.errorDetected = YES;
        return nil;
    }
    
    {
        // Read all the paths in chunks
        uint64_t bytesLeftoverToCopy = filePathSectionSize;
        while (bytesLeftoverToCopy > 0) {
            uint64_t currentBlockSize = (bytesLeftoverToCopy >= PARTIAL_IO_CHUNK_SIZE) ? PARTIAL_IO_CHUNK_SIZE : bytesLeftoverToCopy;
            
            if (![self _readBuffer:fileTableData + (filePathSectionSize - bytesLeftoverToCopy) length:(int32_t)currentBlockSize]) {
                free(fileTableData);
                return nil;
            }
            
            bytesLeftoverToCopy -= currentBlockSize;
        }
    }
    
    // Read all relative file paths separated by null terminators
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *relativeFilePaths = [[NSMutableArray alloc] init];
    uint64_t currentStartIndex = 0;
    for (uint64_t index = 0; index < filePathSectionSize; index++) {
        if (fileTableData[index] == '\0') {
            NSString *relativePath = [fileManager stringWithFileSystemRepresentation:&fileTableData[currentStartIndex] length:index - currentStartIndex];
            if (relativePath == nil) {
                self.errorDetected = YES;
                free(fileTableData);
                return nil;
            }
            
            currentStartIndex = index + 1;
            [relativeFilePaths addObject:relativePath];
        }
    }
    
    free(fileTableData);
    
    return relativeFilePaths;
}

- (BOOL)enumerateItems:(void (^)(SPUDeltaArchiveItem * _Nonnull, BOOL * _Nonnull))itemHandler
{
    // Parse all relative file paths
    NSArray<NSString *> *relativeFilePaths = [self _readRelativeFilePaths];
    if (relativeFilePaths == nil) {
        return NO;
    }
    
    if (relativeFilePaths.count == 0) {
        // No diff changes
        return YES;
    }
    
    // Parse through all commands
    NSMutableArray<SPUDeltaArchiveItem *> *archiveItems = [[NSMutableArray alloc] init];
    {
        uint64_t currentItemIndex = 0;
        while (YES) {
            SPUDeltaItemCommands commands = 0;
            if (![self _readBuffer:&commands length:sizeof(commands)]) {
                break;
            }
            
            // Test if we've reached the end marker
            if (commands == 0) {
                break;
            }
            
            // Check if we need to decode additional data
            uint16_t decodedMode = 0;
            uint64_t decodedDataLength = 0;
            
            if ((commands & SPUDeltaItemCommandExtract) != 0 || (commands & SPUDeltaItemCommandBinaryDiff) != 0) {
                if (![self _readBuffer:&decodedMode length:sizeof(decodedMode)]) {
                    break;
                }
                
                // Decode data length
                // Length doesn't matter for directory names (we already track the name in the relative path)
                if (S_ISREG(decodedMode) || S_ISLNK(decodedMode)) {
                    if (![self _readBuffer:&decodedDataLength length:sizeof(decodedDataLength)]) {
                        break;
                    }
                }
            } else if ((commands & SPUDeltaItemCommandModifyPermissions) != 0) {
                // Decode file permissions
                if (![self _readBuffer:&decodedMode length:sizeof(decodedMode)]) {
                    break;
                }
            }
            
            SPUDeltaArchiveItem *archiveItem = [[SPUDeltaArchiveItem alloc] initWithRelativeFilePath:relativeFilePaths[currentItemIndex] commands:commands permissions:decodedMode];
            
            archiveItem.codedDataLength = decodedDataLength;
            
            [archiveItems addObject:archiveItem];
            
            currentItemIndex++;
        }
    }
    
    if (self.errorDetected) {
        return NO;
    }
    
    // Feed items back to caller
    BOOL exitedEarly = NO;
    for (SPUDeltaArchiveItem *item in archiveItems) {
        itemHandler(item, &exitedEarly);
        if (exitedEarly) {
            break;
        }
    }
    
    return !exitedEarly;
}

- (BOOL)extractItem:(SPUDeltaArchiveItem *)item
{
    NSString *physicalFilePath = item.physicalFilePath;
    assert(physicalFilePath != nil);
    
    SPUDeltaItemCommands commands = item.commands;
    assert((commands & SPUDeltaItemCommandExtract) != 0 || (commands & SPUDeltaItemCommandBinaryDiff) != 0);
    
    uint16_t mode = item.permissions;
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ((commands & SPUDeltaItemCommandBinaryDiff) != 0 || S_ISREG(mode) || S_ISLNK(mode)) {
        // Handle regular files
        // Binary diffs are always on regular files only
        
        uint64_t decodedLength = item.codedDataLength;
        
        if ((commands & SPUDeltaItemCommandBinaryDiff) != 0 || S_ISREG(mode)) {
            // Regular files
            
            const char *physicalFilePathString = physicalFilePath.fileSystemRepresentation;
            FILE *outputFile = fopen(physicalFilePathString, "wb");
            if (outputFile == NULL) {
                self.errorDetected = YES;
                return NO;
            }
            
            if (decodedLength > 0) {
                // Write out archive contents to file in chunks
                
                void *tempBuffer = calloc(1, PARTIAL_IO_CHUNK_SIZE);
                if (tempBuffer == NULL) {
                    self.errorDetected = YES;
                } else {
                    uint64_t bytesLeftoverToCopy = decodedLength;
                    while (bytesLeftoverToCopy > 0) {
                        uint64_t currentBlockSize = (bytesLeftoverToCopy >= PARTIAL_IO_CHUNK_SIZE) ? PARTIAL_IO_CHUNK_SIZE : bytesLeftoverToCopy;
                        
                        if (![self _readBuffer:tempBuffer length:(int32_t)currentBlockSize]) {
                            break;
                        }
                        
                        if (fwrite(tempBuffer, currentBlockSize, 1, outputFile) < 1) {
                            self.errorDetected = YES;
                            break;
                        }
                        
                        bytesLeftoverToCopy -= currentBlockSize;
                    }
                }
            }
            
            fclose(outputFile);
            
            if (self.errorDetected) {
                return NO;
            }
            
            if (chmod(physicalFilePathString, mode) != 0) {
                self.errorDetected = YES;
                return NO;
            }
        } else {
            // Link files
            
            if (PARTIAL_IO_CHUNK_SIZE < decodedLength) {
                // Something is seriously wrong
                self.errorDetected = YES;
                return NO;
            }
            
            void *buffer;
            if (decodedLength == 0) {
                buffer = NULL;
            } else {
                buffer = calloc(1, decodedLength);
                if (buffer == NULL) {
                    self.errorDetected = YES;
                    return NO;
                }
                
                if (![self _readBuffer:buffer length:(int32_t)decodedLength]) {
                    free(buffer);
                    return NO;
                }
            }
            
            NSString *destinationPath = (buffer != NULL) ? [fileManager stringWithFileSystemRepresentation:buffer length:decodedLength] : @"";
            
            free(buffer);
            
            if (destinationPath == nil) {
                self.errorDetected = YES;
                return NO;
            }
            
            NSError *error = nil;
            if (![fileManager createSymbolicLinkAtPath:physicalFilePath withDestinationPath:destinationPath error:&error]) {
                self.errorDetected = YES;
                return NO;
            }
            
            // We shouldn't fail if setting permissions on symlinks fail
            // Apple filesystems have file permissions for symbolic links but other linux file systems don't
            // So this may have no effect on some file systems over the network
            lchmod(physicalFilePath.fileSystemRepresentation, mode);
        }
    } else if (S_ISDIR(mode)) {
        NSError *error = nil;
        if (![fileManager createDirectoryAtPath:physicalFilePath withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions: @(mode)} error:&error]) {
            self.errorDetected = YES;
            return NO;
        }
    }
    
    return YES;
}

- (BOOL)_writeBuffer:(void *)buffer length:(int32_t)length
{
    if (self.errorDetected) {
        return NO;
    }
    
    switch (self.compression) {
        case SPUDeltaCompressionModeNone: {
            BOOL success = (fwrite(buffer, (size_t)length, 1, self.file) == 1);
            if (!success) {
                self.errorDetected = YES;
            }
            
            return success;
        }
        case SPUDeltaCompressionModeBzip2: {
            int bzerror = 0;
            BZ2_bzWrite(&bzerror, self.bzipFile, buffer, length);
            BOOL success = (bzerror == BZ_OK);
            if (!success) {
                self.errorDetected = YES;
            }
            
            return success;
        }
    }
}

- (void)writeHeader:(SPUDeltaArchiveHeader *)header
{
    uint16_t majorVersion = header.majorVersion;
    [self _writeBuffer:&majorVersion length:sizeof(majorVersion)];
    
    uint16_t minorVersion = header.minorVersion;
    [self _writeBuffer:&minorVersion length:sizeof(minorVersion)];
    
    [self _writeBuffer:header.beforeTreeHash length:CC_SHA1_DIGEST_LENGTH];
    [self _writeBuffer:header.afterTreeHash length:CC_SHA1_DIGEST_LENGTH];
}

- (void)addItem:(SPUDeltaArchiveItem *)item
{
    [self.writableItems addObject:item];
}

- (void)_encodeWritableItems
{
    NSArray<SPUDeltaArchiveItem *> *writableItems = self.writableItems;
    if (writableItems == nil) {
        return;
    }
    
    self.writableItems = nil;
    
    // Compute length of path section to write
    uint64_t totalPathLength = 0;
    for (SPUDeltaArchiveItem *item in writableItems) {
        NSString *relativePath = item.relativeFilePath;
        const char *relativePathString = relativePath.UTF8String;
        
        totalPathLength += strlen(relativePathString) + 1;
    }
    
    // Write total expected length of path section
    if (![self _writeBuffer:&totalPathLength length:sizeof(totalPathLength)]) {
        return;
    }
    
    // Write all of the relative paths
    for (SPUDeltaArchiveItem *item in writableItems) {
        NSString *relativePath = item.relativeFilePath;
        
        char pathBuffer[PATH_MAX + 1] = {0};
        if (![relativePath getFileSystemRepresentation:pathBuffer maxLength:PATH_MAX]) {
            self.errorDetected = YES;
            break;
        }
        
        if (![self _writeBuffer:pathBuffer length:(int32_t)strlen(pathBuffer) + 1]) {
            break;
        }
    }
    
    if (self.errorDetected) {
        return;
    }
    
    // Encode the items
    for (SPUDeltaArchiveItem *item in writableItems) {
        // Store commands
        SPUDeltaItemCommands commands = item.commands;
        if (![self _writeBuffer:&commands length:sizeof(commands)]) {
            break;
        }
        
        // Check if we need to encode additional data
        if ((commands & SPUDeltaItemCommandExtract) != 0 || (commands & SPUDeltaItemCommandBinaryDiff) != 0) {
            NSString *physicalPath = item.physicalFilePath;
            assert(physicalPath != nil);
            
            struct stat fileInfo = {0};
            if (lstat(physicalPath.fileSystemRepresentation, &fileInfo) != 0) {
                self.errorDetected = YES;
                break;
            }

            uint16_t originalMode = fileInfo.st_mode;
            item.originalMode = originalMode;
            
            uint16_t encodedMode;
            if ((commands & SPUDeltaItemCommandModifyPermissions) != 0) {
                uint16_t permissions = item.permissions;
                encodedMode = (originalMode & ~PERMISSION_FLAGS) | permissions;
            } else {
                encodedMode = originalMode;
            }
            
            // Store file mode (including desired permissions)
            if (![self _writeBuffer:&encodedMode length:sizeof(encodedMode)]) {
                break;
            }
            
            // Store data length
            // Length doesn't matter for directory names (we already track the name in the relative path)
            if (S_ISREG(originalMode) || S_ISLNK(originalMode)) {
                uint64_t dataLength = (uint64_t)fileInfo.st_size;
                if (![self _writeBuffer:&dataLength length:sizeof(dataLength)]) {
                    break;
                }
                
                item.codedDataLength = dataLength;
            }
        } else if ((commands & SPUDeltaItemCommandModifyPermissions) != 0) {
            // Store file permissions
            uint16_t permissions = item.permissions;
            if (![self _writeBuffer:&permissions length:sizeof(permissions)]) {
                break;
            }
        }
    }
    
    if (self.errorDetected) {
        return;
    }
    
    // Encode end marker
    SPUDeltaItemCommands endCommand = 0;
    if (![self _writeBuffer:&endCommand length:sizeof(endCommand)]) {
        return;
    }
    
    // Encode all of our file contents
    for (SPUDeltaArchiveItem *item in writableItems) {
        SPUDeltaItemCommands commands = item.commands;
        if ((commands & SPUDeltaItemCommandExtract) != 0 || (commands & SPUDeltaItemCommandBinaryDiff) != 0) {
            NSString *physicalPath = item.physicalFilePath;
            assert(physicalPath != nil);
            
            mode_t originalMode = item.originalMode;
            if (S_ISREG(originalMode)) {
                // Write out file contents to archive in chunks
                
                uint64_t totalItemSize = item.codedDataLength;
                if (totalItemSize > 0) {
                    FILE *inputFile = fopen(physicalPath.fileSystemRepresentation, "rb");
                    if (inputFile == NULL) {
                        self.errorDetected = YES;
                        break;
                    }
                    
                    uint8_t *tempBuffer = calloc(1, PARTIAL_IO_CHUNK_SIZE);
                    if (tempBuffer == NULL) {
                        self.errorDetected = YES;
                    } else {
                        uint64_t bytesLeftoverToCopy = totalItemSize;
                        while (bytesLeftoverToCopy > 0) {
                            uint64_t currentBlockSize = (bytesLeftoverToCopy >= PARTIAL_IO_CHUNK_SIZE) ? PARTIAL_IO_CHUNK_SIZE : bytesLeftoverToCopy;
                            
                            if (fread(tempBuffer, currentBlockSize, 1, inputFile) < 1) {
                                self.errorDetected = YES;
                                break;
                            }
                            
                            if (![self _writeBuffer:tempBuffer length:(int32_t)currentBlockSize]) {
                                break;
                            }
                            
                            bytesLeftoverToCopy -= currentBlockSize;
                        }
                    }
                    
                    fclose(inputFile);
                    
                    if (self.errorDetected) {
                        break;
                    }
                }
            } else if (S_ISLNK(originalMode)) {
                char linkDestination[PATH_MAX + 1] = {0};
                ssize_t linkDestinationLength = readlink(physicalPath.fileSystemRepresentation, linkDestination, PATH_MAX);
                if (linkDestinationLength < 0) {
                    self.errorDetected = YES;
                    break;
                }
                
                if (![self _writeBuffer:linkDestination length:(int32_t)strlen(linkDestination)]) {
                    break;
                }
            }
        }
    }
}

- (BOOL)finishEncodingItems
{
    if (self.errorDetected) {
        return NO;
    }
    
    [self _encodeWritableItems];
    
    return !self.errorDetected;
}

@end
