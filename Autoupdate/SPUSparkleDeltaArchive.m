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
#define SPARKLE_BZIP2_ERROR_DOMAIN @"Sparkle BZIP2"

@interface SPUSparkleDeltaArchive ()

@property (nonatomic) FILE *file;
@property (nonatomic) BZFILE *bzipFile;
@property (nonatomic, readonly) NSString *patchFile;
@property (nonatomic) SPUDeltaCompressionMode compression;
@property (nonatomic, readonly) BOOL writeMode;
@property (nonatomic) NSError *error;

@property (nonatomic) NSMutableArray<SPUDeltaArchiveItem *> *writableItems;
@property (nonatomic) int32_t writableCompressionLevel;

@end

@implementation SPUSparkleDeltaArchive

@synthesize file = _file;
@synthesize bzipFile = _bzipFile;
@synthesize patchFile = _patchFile;
@synthesize compression = _compression;
@synthesize writeMode = _writeMode;
@synthesize writableItems = _writableItems;
@synthesize writableCompressionLevel = _writableCompressionLevel;
@synthesize error = _error;

+ (BOOL)maySupportSafeExtraction
{
    return YES;
}

- (instancetype)initWithPatchFileForWriting:(NSString *)patchFile compression:(SPUDeltaCompressionMode)compression compressionLevel:(int32_t)compressionLevel
{
    self = [super init];
    if (self != nil) {
        _patchFile = [patchFile copy];
        _writableItems = [NSMutableArray array];
        _compression = compression;
        _writableCompressionLevel = compressionLevel;
        _writeMode = YES;
    }
    return self;
}

- (instancetype)initWithPatchFileForReading:(NSString *)patchFile
{
    self = [super init];
    if (self != nil) {
        _patchFile = [patchFile copy];
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
    if (self.error != nil) {
        return NO;
    }
    
    switch (self.compression) {
        case SPUDeltaCompressionModeNone: {
            if (fread(buffer, (size_t)length, 1, self.file) < 1) {
                self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to read %d uncompressed bytes from archive.", length] }];
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
                        self.error = [NSError errorWithDomain:SPARKLE_BZIP2_ERROR_DOMAIN code:0 userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Only %d out of %d expected bytes were read from the bz2 archive.", bytesRead, length] }];
                        return NO;
                    } else {
                        return YES;
                    }
                case BZ_IO_ERROR:
                    self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: @"Encountered unexpected IO error when reading compressed bytes from bz2 archive." }];
                    return NO;
                default:
                    self.error = [NSError errorWithDomain:SPARKLE_BZIP2_ERROR_DOMAIN code:bzerror userInfo:@{ NSLocalizedDescriptionKey: @"Encountered unexpected error when reading compressed bytes from bz2 archive." }];
                    return NO;
            }
        }
    }
}

- (nullable SPUDeltaArchiveHeader *)readHeader
{
    NSString *patchFile = self.patchFile;
    
    char patchFilePath[PATH_MAX + 1] = {0};
    if (![patchFile getFileSystemRepresentation:patchFilePath maxLength:sizeof(patchFilePath) - 1]) {
        self.error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to open and represent as a file system representation: %@", patchFile] }];
        return nil;
    }
    
    FILE *file = fopen(patchFilePath, "rb");
    if (file == NULL) {
        self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to open patch file for writing value due to io error: %@", patchFile] }];
        return nil;
    }
    
    self.file = file;
    
    char magic[5] = {0};
    if (fread(magic, sizeof(magic) - 1, 1, file) < 1) {
        self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to read magic value from patch file: %@", patchFile] }];
        return nil;
    }
    
    if (strncmp(magic, SPARKLE_DELTA_FORMAT_MAGIC, sizeof(magic) - 1) != 0) {
        self.error = [NSError errorWithDomain:SPARKLE_DELTA_ARCHIVE_ERROR_DOMAIN code:SPARKLE_DELTA_ARCHIVE_ERROR_CODE_BAD_MAGIC userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Patch file does not have '%@' magic value", @SPARKLE_DELTA_FORMAT_MAGIC] }];
        return nil;
    }
    
    SPUDeltaCompressionMode compression = 0;
    if (fread(&compression, sizeof(compression), 1, file) < 1) {
        self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to read compression value from patch file: %@", patchFile] }];
        return nil;
    }
    
    self.compression = compression;
    
    switch (compression) {
        case SPUDeltaCompressionModeNone:
            break;
        case SPUDeltaCompressionModeBzip2: {
            int bzerror = 0;
            
            BZFILE *bzipFile = BZ2_bzReadOpen(&bzerror, file, 0, 0, NULL, 0);
            if (bzipFile == NULL) {
                switch (bzerror) {
                    case BZ_IO_ERROR:
                        self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to open patch as bz2 file due to io error: %@", patchFile] }];
                        break;
                    default:
                        self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:bzerror userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to open patch as bz2 file: %@", patchFile] }];
                        break;
                }
                return nil;
            }
            
            self.bzipFile = bzipFile;
            
            break;
        }
        default:
            self.error = [NSError errorWithDomain:SPARKLE_DELTA_ARCHIVE_ERROR_DOMAIN code:SPARKLE_DELTA_ARCHIVE_ERROR_CODE_BAD_COMPRESSION_VALUE userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Compression value read %d is not recognized.", compression] }];
            return nil;
    }
    
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
    if (self.error != nil) {
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
        self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to calloc() %llu bytes for relative file paths.", filePathSectionSize] }];
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
                self.error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Relative path cannot be decoded as a file system representation: %@", relativePath] }];
                
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

- (void)enumerateItems:(void (^)(SPUDeltaArchiveItem * _Nonnull, BOOL * _Nonnull))itemHandler
{
    // Parse all relative file paths
    NSArray<NSString *> *relativeFilePaths = [self _readRelativeFilePaths];
    if (relativeFilePaths == nil) {
        return;
    }
    
    if (relativeFilePaths.count == 0) {
        // No diff changes
        return;
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
    
    if (self.error != nil) {
        return;
    }
    
    // Feed items back to caller
    BOOL exitedEarly = NO;
    for (SPUDeltaArchiveItem *item in archiveItems) {
        itemHandler(item, &exitedEarly);
        if (exitedEarly) {
            break;
        }
    }
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
            
            char physicalFilePathString[PATH_MAX + 1] = {0};
            if (![physicalFilePath getFileSystemRepresentation:physicalFilePathString maxLength:sizeof(physicalFilePathString) - 1]) {
                self.error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Path to extract cannot be decoded and expressed as a file system representation: %@", physicalFilePath] }];
                return NO;
            }
            
            FILE *outputFile = fopen(physicalFilePathString, "wb");
            if (outputFile == NULL) {
                self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to fopen() %@", physicalFilePath] }];
                return NO;
            }
            
            if (decodedLength > 0) {
                // Write out archive contents to file in chunks
                
                void *tempBuffer = calloc(1, PARTIAL_IO_CHUNK_SIZE);
                if (tempBuffer == NULL) {
                    self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to calloc() %d bytes for chunk.", PARTIAL_IO_CHUNK_SIZE] }];
                } else {
                    uint64_t bytesLeftoverToCopy = decodedLength;
                    while (bytesLeftoverToCopy > 0) {
                        uint64_t currentBlockSize = (bytesLeftoverToCopy >= PARTIAL_IO_CHUNK_SIZE) ? PARTIAL_IO_CHUNK_SIZE : bytesLeftoverToCopy;
                        
                        if (![self _readBuffer:tempBuffer length:(int32_t)currentBlockSize]) {
                            break;
                        }
                        
                        if (fwrite(tempBuffer, currentBlockSize, 1, outputFile) < 1) {
                            self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to fwrite() %llu bytes during extraction.", currentBlockSize] }];
                            break;
                        }
                        
                        bytesLeftoverToCopy -= currentBlockSize;
                    }
                }
            }
            
            fclose(outputFile);
            
            if (self.error != nil) {
                return NO;
            }
            
            if (chmod(physicalFilePathString, mode) != 0) {
                self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to chmod() mode %d on %@", mode, physicalFilePath] }];
                return NO;
            }
        } else {
            // Link files
            
            if (PARTIAL_IO_CHUNK_SIZE < decodedLength) {
                // Something is seriously wrong
                self.error = [NSError errorWithDomain:SPARKLE_DELTA_ARCHIVE_ERROR_DOMAIN code:SPARKLE_DELTA_ARCHIVE_ERROR_CODE_BAD_CHUNK_SIZE userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"PARTIAL_IO_CHUNK_SIZE (%d) < decodedLength (%llu)", PARTIAL_IO_CHUNK_SIZE, decodedLength] }];
                return NO;
            }
            
            void *buffer;
            if (decodedLength == 0) {
                buffer = NULL;
            } else {
                buffer = calloc(1, decodedLength);
                if (buffer == NULL) {
                    self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to calloc() %llu bytes for link %@", decodedLength, physicalFilePath] }];
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
                self.error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Destination path for link %@ cannot be created in a file system representation: %@",physicalFilePath, destinationPath] }];
                return NO;
            }
            
            NSError *createLinkError = nil;
            if (![fileManager createSymbolicLinkAtPath:physicalFilePath withDestinationPath:destinationPath error:&createLinkError]) {
                self.error = createLinkError;
                return NO;
            }
            
            char physicalFilePathString[PATH_MAX + 1] = {0};
            if (![physicalFilePath getFileSystemRepresentation:physicalFilePathString maxLength:sizeof(physicalFilePathString) - 1]) {
                self.error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Link path to extract cannot be decoded and expressed as a file system representation: %@", physicalFilePath] }];
                return NO;
            }
            
            // We shouldn't fail if setting permissions on symlinks fail
            // Apple filesystems have file permissions for symbolic links but other linux file systems don't
            // So this may have no effect on some file systems over the network
            lchmod(physicalFilePathString, mode);
        }
    } else if (S_ISDIR(mode)) {
        NSError *createDirectoryError = nil;
        if (![fileManager createDirectoryAtPath:physicalFilePath withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions: @(mode)} error:&createDirectoryError]) {
            self.error = createDirectoryError;
            return NO;
        }
    }
    
    return YES;
}

- (BOOL)_writeBuffer:(void *)buffer length:(int32_t)length
{
    if (self.error != nil) {
        return NO;
    }
    
    switch (self.compression) {
        case SPUDeltaCompressionModeNone: {
            BOOL success = (fwrite(buffer, (size_t)length, 1, self.file) == 1);
            if (!success) {
                self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to write %d uncompressed bytes.", length] }];
            }
            
            return success;
        }
        case SPUDeltaCompressionModeBzip2: {
            int bzerror = 0;
            BZ2_bzWrite(&bzerror, self.bzipFile, buffer, length);
            switch (bzerror) {
                case BZ_OK:
                    return YES;
                case BZ_IO_ERROR:
                    self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to write %d compressed bz2 bytes due to io error.", length] }];
                    return NO;
                default:
                    self.error = [NSError errorWithDomain:SPARKLE_BZIP2_ERROR_DOMAIN code:bzerror userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to write %d compressed bz2 bytes.", length] }];
                    return NO;
            }
        }
    }
}

- (void)writeHeader:(SPUDeltaArchiveHeader *)header
{
    char patchFilePath[PATH_MAX + 1] = {0};
    if (![self.patchFile getFileSystemRepresentation:patchFilePath maxLength:sizeof(patchFilePath) - 1]) {
        self.error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to open header and represent as a file system representation: %@", self.patchFile] }];
        return;
    }
    
    FILE *file = fopen(patchFilePath, "wb");
    if (file == NULL) {
        self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to open patch file for writing: %@", self.patchFile] }];
        return;
    }
    
    self.file = file;
    
    char magic[] = SPARKLE_DELTA_FORMAT_MAGIC;
    if (fwrite(magic, sizeof(magic) - 1, 1, file) < 1) {
        self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: @"Failed to write magic value due to io error" }];
        return;
    }
    
    SPUDeltaCompressionMode compression = self.compression;
    if (fwrite(&compression, sizeof(compression), 1, file) < 1) {
        self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: @"Failed to write compression value due to io error" }];
        return;
    }
    
    if (compression == SPUDeltaCompressionModeBzip2) {
        int bzerror = 0;
        // Compression level can be 1 - 9
        int blockSize100k = self.writableCompressionLevel;
        
        BZFILE *bzipFile = BZ2_bzWriteOpen(&bzerror, file, blockSize100k, 0, 0);
        if (bzipFile == NULL) {
            switch (bzerror) {
                case BZ_IO_ERROR:
                    self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: @"Failed to open bz2 stream for writing due to io error" }];
                    break;
                default:
                    self.error = [NSError errorWithDomain:SPARKLE_BZIP2_ERROR_DOMAIN code:bzerror userInfo:@{ NSLocalizedDescriptionKey: @"Failed to open bz2 stream for writing" }];
                    break;
            }
            
            return;
        }
        
        self.bzipFile = bzipFile;
    }
    
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

- (void)finishEncodingItems
{
    if (self.error != nil) {
        return;
    }
    
    NSArray<SPUDeltaArchiveItem *> *writableItems = self.writableItems;
    
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
            self.error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Relative path cannot be encoded and expressed as a file system representation: %@", relativePath] }];
            break;
        }
        
        if (![self _writeBuffer:pathBuffer length:(int32_t)strlen(pathBuffer) + 1]) {
            break;
        }
    }
    
    if (self.error != nil) {
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
            
            char physicalFilePathString[PATH_MAX + 1] = {0};
            if (![physicalPath getFileSystemRepresentation:physicalFilePathString maxLength:sizeof(physicalFilePathString) - 1]) {
                self.error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Path cannot be decoded and expressed as a file system representation while encoding items: %@", physicalPath] }];
                break;
            }
            
            struct stat fileInfo = {0};
            if (lstat(physicalFilePathString, &fileInfo) != 0) {
                self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to lstat() on %@", physicalPath] }];
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
    
    if (self.error != nil) {
        return;
    }
    
    // Encode end command marker
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
                    char physicalFilePathString[PATH_MAX + 1] = {0};
                    if (![physicalPath getFileSystemRepresentation:physicalFilePathString maxLength:sizeof(physicalFilePathString) - 1]) {
                        self.error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Path to finish encoding cannot be decoded and expressed as a file system representation: %@", physicalPath] }];
                        break;
                    }
                    
                    FILE *inputFile = fopen(physicalFilePathString, "rb");
                    if (inputFile == NULL) {
                        self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to open file for reading while encoding items: %@", physicalPath] }];
                        break;
                    }
                    
                    uint8_t *tempBuffer = calloc(1, PARTIAL_IO_CHUNK_SIZE);
                    if (tempBuffer == NULL) {
                        self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to calloc() %d chunk bytes while encoding items", PARTIAL_IO_CHUNK_SIZE] }];
                    } else {
                        uint64_t bytesLeftoverToCopy = totalItemSize;
                        while (bytesLeftoverToCopy > 0) {
                            uint64_t currentBlockSize = (bytesLeftoverToCopy >= PARTIAL_IO_CHUNK_SIZE) ? PARTIAL_IO_CHUNK_SIZE : bytesLeftoverToCopy;
                            
                            if (fread(tempBuffer, currentBlockSize, 1, inputFile) < 1) {
                                self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to read %llu chunk bytes while encoding items", currentBlockSize] }];
                                break;
                            }
                            
                            if (![self _writeBuffer:tempBuffer length:(int32_t)currentBlockSize]) {
                                break;
                            }
                            
                            bytesLeftoverToCopy -= currentBlockSize;
                        }
                    }
                    
                    fclose(inputFile);
                    
                    if (self.error != nil) {
                        break;
                    }
                }
            } else if (S_ISLNK(originalMode)) {
                char physicalFilePathString[PATH_MAX + 1] = {0};
                if (![physicalPath getFileSystemRepresentation:physicalFilePathString maxLength:sizeof(physicalFilePathString) - 1]) {
                    self.error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Link path to finish encoding cannot be decoded and expressed as a file system representation: %@", physicalPath] }];
                    break;
                }
                
                char linkDestination[PATH_MAX + 1] = {0};
                ssize_t linkDestinationLength = readlink(physicalFilePathString, linkDestination, PATH_MAX);
                if (linkDestinationLength < 0) {
                    self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to readlink() file at %@", physicalPath] }];
                    break;
                }
                
                if (![self _writeBuffer:linkDestination length:(int32_t)strlen(linkDestination)]) {
                    break;
                }
            }
        }
    }
}

@end
