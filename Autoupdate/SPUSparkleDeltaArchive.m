//
//  SPUSparkleDeltaArchive.m
//  Sparkle
//
//  Created by Mayur Pawashe on 12/30/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#import "SPUSparkleDeltaArchive.h"
#import <sys/stat.h>
#import <CommonCrypto/CommonDigest.h>
#import "SUBinaryDeltaCommon.h"
#import <compression.h>

#if SPARKLE_BUILD_BZIP2_DELTA_SUPPORT
#import <bzlib.h>
#endif

#include "AppKitPrevention.h"

#define SPARKLE_DELTA_FORMAT_MAGIC "spk!"
#define PARTIAL_IO_CHUNK_SIZE 16384 // this must be >= PATH_MAX
#define COMPRESSION_BUFFER_SIZE 65536
#define SPARKLE_BZIP2_ERROR_DOMAIN @"Sparkle BZIP2"
#define SPARKLE_COMPRESSION_ERROR_DOMAIN @"Sparkle Compression"

typedef struct
{
    uint8_t compressionLevel : 4;
    uint8_t reserved : 3;
    bool fileSystemCompression : 1;
} SparkleDeltaArchiveMetadata;

@implementation SPUSparkleDeltaArchive
{
    FILE *_file;
#if SPARKLE_BUILD_BZIP2_DELTA_SUPPORT
    BZFILE *_bzipFile;
#endif
    NSString *_patchFile;
    NSError *_error;
    void *_partialChunkBuffer;
    void *_compressionBuffer;
    NSMutableArray<SPUDeltaArchiveItem *> *_writableItems;
    
    compression_stream _compressionStream;
    SPUDeltaCompressionMode _compression;
    
    BOOL _initializedCompressionStream;
    BOOL _writeMode;
}

@synthesize error = _error;

+ (BOOL)maySupportSafeExtraction
{
    return YES;
}

- (instancetype)initWithPatchFileForWriting:(NSString *)patchFile
{
    self = [super init];
    if (self != nil) {
        _patchFile = [patchFile copy];
        _writableItems = [NSMutableArray array];
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
#if SPARKLE_BUILD_BZIP2_DELTA_SUPPORT
    if (_bzipFile != NULL) {
        if (!_writeMode) {
            int bzerror = 0;
            BZ2_bzReadClose(&bzerror, _bzipFile);
        }
        
        _bzipFile = NULL;
    } else
#endif
    if (_initializedCompressionStream) {
        compression_stream_destroy(&_compressionStream);
        _initializedCompressionStream = NO;
    }
    
    if (_file != NULL) {
        fclose(_file);
        _file = NULL;
    }
    
    free(_partialChunkBuffer);
    _partialChunkBuffer = NULL;
    
    free(_compressionBuffer);
    _compressionBuffer = NULL;
}

- (BOOL)createBuffers SPU_OBJC_DIRECT
{
    _partialChunkBuffer = calloc(1, PARTIAL_IO_CHUNK_SIZE);
    if (_partialChunkBuffer == NULL) {
        _error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to calloc() %d bytes for partial chunk buffer.", PARTIAL_IO_CHUNK_SIZE] }];
        return NO;
    }
    
    if (_initializedCompressionStream) {
        _compressionBuffer = calloc(1, COMPRESSION_BUFFER_SIZE);
        if (_compressionBuffer == NULL) {
            _error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to calloc() %d bytes for compression buffer.", COMPRESSION_BUFFER_SIZE] }];
            return NO;
        }
    }
    
    return YES;
}

- (BOOL)_readBuffer:(void *)buffer length:(int32_t)length SPU_OBJC_DIRECT
{
    if (_error != nil) {
        return NO;
    }
    
    switch (_compression) {
        case SPUDeltaCompressionModeNone: {
            if (fread(buffer, (size_t)length, 1, _file) < 1) {
                _error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to read %d uncompressed bytes from archive.", length] }];
                return NO;
            } else {
                return YES;
            }
        }
        case SPUDeltaCompressionModeBzip2:
        {
#if SPARKLE_BUILD_BZIP2_DELTA_SUPPORT
            int bzerror = 0;
            int bytesRead = BZ2_bzRead(&bzerror, _bzipFile, buffer, length);
            
            switch (bzerror) {
                case BZ_OK:
                case BZ_STREAM_END:
                    if (bytesRead < length) {
                        _error = [NSError errorWithDomain:SPARKLE_BZIP2_ERROR_DOMAIN code:0 userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Only %d out of %d expected bytes were read from the bz2 archive.", bytesRead, length] }];
                        return NO;
                    } else {
                        return YES;
                    }
                case BZ_IO_ERROR:
                    _error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: @"Encountered unexpected IO error when reading compressed bytes from bz2 archive." }];
                    return NO;
                default:
                    _error = [NSError errorWithDomain:SPARKLE_BZIP2_ERROR_DOMAIN code:bzerror userInfo:@{ NSLocalizedDescriptionKey: @"Encountered unexpected error when reading compressed bytes from bz2 archive." }];
                    return NO;
            }
#else
            return NO;
#endif
        }
        case SPUDeltaCompressionModeLZMA:
        case SPUDeltaCompressionModeLZFSE:
        case SPUDeltaCompressionModeLZ4:
        case SPUDeltaCompressionModeZLIB: {
            FILE *file = _file;
            void *compressionBuffer = _compressionBuffer;
            
            _compressionStream.dst_ptr = buffer;
            _compressionStream.dst_size = (size_t)length;
            
            while (_compressionStream.dst_size > 0) {
                // Go through the current incomplete chunk before reading another one
                
                if (_compressionStream.src_size == 0) {
                    size_t bytesRead = fread(compressionBuffer, 1, COMPRESSION_BUFFER_SIZE, file);
                    if (bytesRead < COMPRESSION_BUFFER_SIZE) {
                        if (feof(file) == 0) {
                            _error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to read %d compressed raw bytes from archive.", length] }];
                            return NO;
                        }
                    }
                    
                    // Reset source buffer
                    _compressionStream.src_ptr = compressionBuffer;
                    _compressionStream.src_size = bytesRead;
                }
                
                compression_status status = compression_stream_process(&_compressionStream, feof(file) != 0 ? COMPRESSION_STREAM_FINALIZE : 0);
                if (status == COMPRESSION_STATUS_ERROR) {
                    _error = [NSError errorWithDomain:SPARKLE_COMPRESSION_ERROR_DOMAIN code:COMPRESSION_STATUS_ERROR userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to read %d compressed bytes.", length] }];
                    return NO;
                }
                
                if (status == COMPRESSION_STATUS_END && _compressionStream.dst_size > 0) {
                    // We're expecting more bytes but we can't read any more bytes
                    _error = [NSError errorWithDomain:SPARKLE_DELTA_ARCHIVE_ERROR_DOMAIN code:-1 userInfo:@{ NSLocalizedDescriptionKey: @"Failed to decompress and read bytes because we reached EOF" }];
                    return NO;
                }
            }
            
            return YES;
        }
    }
}

static compression_algorithm compressionAlgorithmForMode(SPUDeltaCompressionMode compressionMode)
{
    switch (compressionMode) {
    case SPUDeltaCompressionModeLZMA:
        return COMPRESSION_LZMA;
    case SPUDeltaCompressionModeLZFSE:
        return COMPRESSION_LZFSE;
    case SPUDeltaCompressionModeLZ4:
        return COMPRESSION_LZ4;
    case SPUDeltaCompressionModeZLIB:
        return COMPRESSION_ZLIB;
    case SPUDeltaCompressionModeNone:
    case SPUDeltaCompressionModeBzip2:
        assert(false);
    }
    
    assert(false);
}

- (nullable SPUDeltaArchiveHeader *)readHeader
{
    NSString *patchFile = _patchFile;
    
    char patchFilePath[PATH_MAX + 1] = {0};
    if (![patchFile getFileSystemRepresentation:patchFilePath maxLength:sizeof(patchFilePath) - 1]) {
        _error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to open and represent as a file system representation: %@", patchFile] }];
        return nil;
    }
    
    FILE *file = fopen(patchFilePath, "rb");
    if (file == NULL) {
        _error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to open patch file for writing value due to io error: %@", patchFile] }];
        return nil;
    }
    
    _file = file;
    
    char magic[5] = {0};
    if (fread(magic, sizeof(magic) - 1, 1, file) < 1) {
        _error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to read magic value from patch file: %@", patchFile] }];
        return nil;
    }
    
    if (strncmp(magic, SPARKLE_DELTA_FORMAT_MAGIC, sizeof(magic) - 1) != 0) {
        _error = [NSError errorWithDomain:SPARKLE_DELTA_ARCHIVE_ERROR_DOMAIN code:SPARKLE_DELTA_ARCHIVE_ERROR_CODE_BAD_MAGIC userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Patch file does not have '%@' magic value", @SPARKLE_DELTA_FORMAT_MAGIC] }];
        return nil;
    }
    
    SPUDeltaCompressionMode compression = 0;
    if (fread(&compression, sizeof(compression), 1, file) < 1) {
        _error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to read compression value from patch file: %@", patchFile] }];
        return nil;
    }
    
    _compression = compression;
    
    SparkleDeltaArchiveMetadata metadata = {0};
    if (fread(&metadata, sizeof(metadata), 1, file) < 1) {
        _error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to read compression level value from patch file: %@", patchFile] }];
        return nil;
    }
    
    switch (compression) {
        case SPUDeltaCompressionModeNone:
            break;
        case SPUDeltaCompressionModeBzip2: {
#if SPARKLE_BUILD_BZIP2_DELTA_SUPPORT
            int bzerror = 0;
            
            BZFILE *bzipFile = BZ2_bzReadOpen(&bzerror, file, 0, 0, NULL, 0);
            if (bzipFile == NULL) {
                switch (bzerror) {
                    case BZ_IO_ERROR:
                        _error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to open patch as bz2 file due to io error: %@", patchFile] }];
                        break;
                    default:
                        _error = [NSError errorWithDomain:NSPOSIXErrorDomain code:bzerror userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to open patch as bz2 file: %@", patchFile] }];
                        break;
                }
                return nil;
            }
            
            _bzipFile = bzipFile;
            
            break;
#else
            _error = [NSError errorWithDomain:SPARKLE_BZIP2_ERROR_DOMAIN code:-1 userInfo:@{ NSLocalizedDescriptionKey: @"Failed to open patch as bz2 file because bzip2 support is disabled" }];
            return nil;
#endif
        }
        case SPUDeltaCompressionModeLZMA:
        case SPUDeltaCompressionModeLZFSE:
        case SPUDeltaCompressionModeLZ4:
        case SPUDeltaCompressionModeZLIB: {
            if (compression_stream_init(&_compressionStream, COMPRESSION_STREAM_DECODE, compressionAlgorithmForMode(compression)) != COMPRESSION_STATUS_OK) {
                _error = [NSError errorWithDomain:SPARKLE_COMPRESSION_ERROR_DOMAIN code:COMPRESSION_STATUS_ERROR userInfo:@{ NSLocalizedDescriptionKey: @"Failed to open compression stream for reading" }];
                return nil;
            }
            
            _initializedCompressionStream = YES;
            
            break;
        }
        default:
            _error = [NSError errorWithDomain:SPARKLE_DELTA_ARCHIVE_ERROR_DOMAIN code:SPARKLE_DELTA_ARCHIVE_ERROR_CODE_BAD_COMPRESSION_VALUE userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Compression value read %d is not recognized.", compression] }];
            return nil;
    }
    
    if (![self createBuffers]) {
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
    
    unsigned char beforeTreeHash[BINARY_DELTA_HASH_LENGTH] = {0};
    if (![self _readBuffer:beforeTreeHash length:sizeof(beforeTreeHash)]) {
        return nil;
    }
    
    unsigned char afterTreeHash[BINARY_DELTA_HASH_LENGTH] = {0};
    if (![self _readBuffer:afterTreeHash length:sizeof(afterTreeHash)]) {
        return nil;
    }
    
    NSDate *bundleCreationDate;
    if (majorVersion >= SUBinaryDeltaMajorVersion4) {
        double bundleCreationTimeInterval = 0;
        if (![self _readBuffer:&bundleCreationTimeInterval length:sizeof(bundleCreationTimeInterval)]) {
            return nil;
        }
        
        bundleCreationDate = (bundleCreationTimeInterval != 0.0) ? [NSDate dateWithTimeIntervalSinceReferenceDate:bundleCreationTimeInterval] : nil;
    } else {
        bundleCreationDate = nil;
    }
    
    return [[SPUDeltaArchiveHeader alloc] initWithCompression:compression compressionLevel:metadata.compressionLevel fileSystemCompression:metadata.fileSystemCompression majorVersion:majorVersion minorVersion:minorVersion beforeTreeHash:beforeTreeHash afterTreeHash:afterTreeHash bundleCreationDate:bundleCreationDate];
}

- (NSArray<NSString *> *)_readRelativeFilePaths SPU_OBJC_DIRECT
{
    if (_error != nil) {
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
        _error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to calloc() %llu bytes for relative file paths.", filePathSectionSize] }];
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
                _error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Relative path cannot be decoded as a file system representation: %@", relativePath] }];
                
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
    
    if (relativeFilePaths.count > UINT32_MAX) {
        // Very unlikely but we should guard against this
        // Clones rely on 32-bit indexes
        _error = [NSError errorWithDomain:SPARKLE_DELTA_ARCHIVE_ERROR_DOMAIN code:SPARKLE_DELTA_ARCHIVE_ERROR_CODE_TOO_MANY_FILES userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"There are too many file entries to apply a patch for (more than %u)", UINT32_MAX] }];
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
            
            // Test if we're done
            if (commands == SPUDeltaItemCommandEndMarker) {
                break;
            }
            
            // Check if we need to decode additional data
            uint16_t decodedMode = 0;
            uint64_t decodedDataLength = 0;
            NSString *clonedRelativePath = nil;
            
            if ((commands & SPUDeltaItemCommandClone) != 0) {
                if ((commands & SPUDeltaItemCommandModifyPermissions) != 0) {
                    // Decode file permission changes for clone
                    if (![self _readBuffer:&decodedMode length:sizeof(decodedMode)]) {
                        break;
                    }
                }
                
                // Decode relative file path for original source file
                uint32_t cloneRelativePathIndex = 0;
                if (![self _readBuffer:&cloneRelativePathIndex length:sizeof(cloneRelativePathIndex)]) {
                    break;
                }
                
                if ((NSUInteger)cloneRelativePathIndex >= relativeFilePaths.count) {
                    _error = [NSError errorWithDomain:SPARKLE_DELTA_ARCHIVE_ERROR_DOMAIN code:SPARKLE_DELTA_ARCHIVE_ERROR_CODE_BAD_CLONE_LOOKUP userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Index %u is past relative path table bounds of length %lu", cloneRelativePathIndex, (unsigned long)relativeFilePaths.count] }];
                    break;
                }
                
                clonedRelativePath = relativeFilePaths[cloneRelativePathIndex];
                
                if ((commands & SPUDeltaItemCommandBinaryDiff) != 0) {
                    if (![self _readBuffer:&decodedDataLength length:sizeof(decodedDataLength)]) {
                        break;
                    }
                }
            } else if ((commands & SPUDeltaItemCommandBinaryDiff) != 0) {
                // Decode file permission changes if available
                if ((commands & SPUDeltaItemCommandModifyPermissions) != 0) {
                    if (![self _readBuffer:&decodedMode length:sizeof(decodedMode)]) {
                        break;
                    }
                }
                
                // Decode data length
                if (![self _readBuffer:&decodedDataLength length:sizeof(decodedDataLength)]) {
                    break;
                }
            } else if ((commands & SPUDeltaItemCommandExtract) != 0) {
                // Decode permissions/mode
                if (![self _readBuffer:&decodedMode length:sizeof(decodedMode)]) {
                    break;
                }
                
                // Decode data length
                // Length doesn't matter for directory names (we already track the name in the relative path)
                if (S_ISREG(decodedMode)) {
                    if (![self _readBuffer:&decodedDataLength length:sizeof(decodedDataLength)]) {
                        break;
                    }
                } else if (S_ISLNK(decodedMode)) {
                    uint16_t decodedLinkLength = 0;
                    if (![self _readBuffer:&decodedLinkLength length:sizeof(decodedLinkLength)]) {
                        break;
                    }
                    
                    decodedDataLength = decodedLinkLength;
                }
            } else if ((commands & SPUDeltaItemCommandModifyPermissions) != 0) {
                // Decode file permissions
                if (![self _readBuffer:&decodedMode length:sizeof(decodedMode)]) {
                    break;
                }
            }
            
            SPUDeltaArchiveItem *archiveItem = [[SPUDeltaArchiveItem alloc] initWithRelativeFilePath:relativeFilePaths[currentItemIndex] commands:commands mode:decodedMode];
            
            archiveItem.codedDataLength = decodedDataLength;
            archiveItem.clonedRelativePath = clonedRelativePath;
            
            [archiveItems addObject:archiveItem];
            
            currentItemIndex++;
        }
    }
    
    if (_error != nil) {
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
    NSString *itemFilePath = item.itemFilePath;
    assert(itemFilePath != nil);
    
    SPUDeltaItemCommands commands = item.commands;
    assert((commands & SPUDeltaItemCommandExtract) != 0 || (commands & SPUDeltaItemCommandBinaryDiff) != 0);
    
    uint16_t mode = item.mode;
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ((commands & SPUDeltaItemCommandBinaryDiff) != 0 || S_ISREG(mode) || S_ISLNK(mode)) {
        // Handle regular files
        // Binary diffs are always on regular files only
        
        uint64_t decodedLength = item.codedDataLength;
        
        if ((commands & SPUDeltaItemCommandBinaryDiff) != 0 || S_ISREG(mode)) {
            // Regular files
            
            [fileManager removeItemAtPath:itemFilePath error:NULL];
            
            char itemFilePathString[PATH_MAX + 1] = {0};
            if (![itemFilePath getFileSystemRepresentation:itemFilePathString maxLength:sizeof(itemFilePathString) - 1]) {
                _error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Path to extract cannot be decoded and expressed as a file system representation: %@", itemFilePath] }];
                return NO;
            }
            
            FILE *outputFile = fopen(itemFilePathString, "wb");
            if (outputFile == NULL) {
                _error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to fopen() %@", itemFilePath] }];
                return NO;
            }
            
            if (decodedLength > 0) {
                // Write out archive contents to file in chunks
                
                uint64_t bytesLeftoverToCopy = decodedLength;
                while (bytesLeftoverToCopy > 0) {
                    uint64_t currentBlockSize = (bytesLeftoverToCopy >= PARTIAL_IO_CHUNK_SIZE) ? PARTIAL_IO_CHUNK_SIZE : bytesLeftoverToCopy;
                    
                    void *tempBuffer = _partialChunkBuffer;
                    
                    if (![self _readBuffer:tempBuffer length:(int32_t)currentBlockSize]) {
                        break;
                    }
                    
                    if (fwrite(tempBuffer, currentBlockSize, 1, outputFile) < 1) {
                        _error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to fwrite() %llu bytes during extraction.", currentBlockSize] }];
                        break;
                    }
                    
                    bytesLeftoverToCopy -= currentBlockSize;
                }
            }
            
            fclose(outputFile);
            
            if (_error != nil) {
                return NO;
            }
            
            if ((commands & SPUDeltaItemCommandExtract) != 0 && chmod(itemFilePathString, mode) != 0) {
                _error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to chmod() mode %d on %@", mode, itemFilePath] }];
                return NO;
            }
        } else {
            // Link files
            
            if (PARTIAL_IO_CHUNK_SIZE < decodedLength) {
                // Something is seriously wrong
                _error = [NSError errorWithDomain:SPARKLE_DELTA_ARCHIVE_ERROR_DOMAIN code:SPARKLE_DELTA_ARCHIVE_ERROR_CODE_BAD_CHUNK_SIZE userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"PARTIAL_IO_CHUNK_SIZE (%d) < decodedLength (%llu)", PARTIAL_IO_CHUNK_SIZE, decodedLength] }];
                return NO;
            }
            
            if (decodedLength > PATH_MAX) {
                // Link is too long
                _error = [NSError errorWithDomain:SPARKLE_DELTA_ARCHIVE_ERROR_DOMAIN code:SPARKLE_DELTA_ARCHIVE_ERROR_CODE_LINK_TOO_LONG userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Decoded length for link (%llu) is too long.", decodedLength] }];
                return NO;
            }
            
            char buffer[PATH_MAX + 1] = {0};
            if (![self _readBuffer:buffer length:(int32_t)decodedLength]) {
                return NO;
            }
            
            NSString *destinationPath = [fileManager stringWithFileSystemRepresentation:buffer length:decodedLength];
            
            if (destinationPath == nil) {
                _error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Destination path for link %@ cannot be created in a file system representation: %@",itemFilePath, destinationPath] }];
                return NO;
            }
            
            [fileManager removeItemAtPath:itemFilePath error:NULL];
            
            NSError *createLinkError = nil;
            if (![fileManager createSymbolicLinkAtPath:itemFilePath withDestinationPath:destinationPath error:&createLinkError]) {
                _error = createLinkError;
                return NO;
            }
            
            char itemFilePathString[PATH_MAX + 1] = {0};
            if (![itemFilePath getFileSystemRepresentation:itemFilePathString maxLength:sizeof(itemFilePathString) - 1]) {
                _error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Link path to extract cannot be decoded and expressed as a file system representation: %@", itemFilePath] }];
                return NO;
            }
            
            // We shouldn't fail if setting permissions on symlinks fail
            // Apple filesystems have file permissions for symbolic links but other linux file systems don't
            // So this may have no effect on some file systems over the network
            lchmod(itemFilePathString, mode);
        }
    } else if (S_ISDIR(mode)) {
        NSError *createDirectoryError = nil;
        if (![fileManager createDirectoryAtPath:itemFilePath withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions: @(mode)} error:&createDirectoryError]) {
            _error = createDirectoryError;
            return NO;
        }
    }
    
    return YES;
}

- (BOOL)_writeBuffer:(void *)buffer length:(int32_t)length SPU_OBJC_DIRECT
{
    if (_error != nil) {
        return NO;
    }
    
    switch (_compression) {
        case SPUDeltaCompressionModeNone: {
            BOOL success = (fwrite(buffer, (size_t)length, 1, _file) == 1);
            if (!success) {
                _error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to write %d uncompressed bytes.", length] }];
            }
            
            return success;
        }
        case SPUDeltaCompressionModeBzip2:
        {
#if SPARKLE_BUILD_BZIP2_DELTA_SUPPORT
            int bzerror = 0;
            BZ2_bzWrite(&bzerror, _bzipFile, buffer, length);
            switch (bzerror) {
                case BZ_OK:
                    return YES;
                case BZ_IO_ERROR:
                    _error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to write %d compressed bz2 bytes due to io error.", length] }];
                    return NO;
                default:
                    _error = [NSError errorWithDomain:SPARKLE_BZIP2_ERROR_DOMAIN code:bzerror userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to write %d compressed bz2 bytes.", length] }];
                    return NO;
            }
#else
            return NO;
#endif
        }
        case SPUDeltaCompressionModeLZMA:
        case SPUDeltaCompressionModeLZFSE:
        case SPUDeltaCompressionModeLZ4:
        case SPUDeltaCompressionModeZLIB: {
            _compressionStream.src_ptr = buffer;
            _compressionStream.src_size = (size_t)length;
            
            FILE *file = _file;
            void *compressionBuffer = _compressionBuffer;
            while (_compressionStream.src_size > 0) {
                // Reset destination buffer
                _compressionStream.dst_ptr = compressionBuffer;
                _compressionStream.dst_size = COMPRESSION_BUFFER_SIZE;
                
                if (compression_stream_process(&_compressionStream, 0) == COMPRESSION_STATUS_ERROR) {
                    _error = [NSError errorWithDomain:SPARKLE_COMPRESSION_ERROR_DOMAIN code:COMPRESSION_STATUS_ERROR userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to write %d compressed bytes.", length] }];
                    return NO;
                }
                
                size_t compressedBytesWritten = (size_t)(_compressionStream.dst_ptr - (uint8_t *)compressionBuffer);
                if (compressedBytesWritten > 0 && fwrite(compressionBuffer, compressedBytesWritten, 1, file) < 1) {
                    _error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to write %zu compressed bytes.", compressedBytesWritten] }];
                    return NO;
                }
            }
            
            return YES;
        }
    }
}

- (void)writeHeader:(SPUDeltaArchiveHeader *)header
{
    char patchFilePath[PATH_MAX + 1] = {0};
    if (![_patchFile getFileSystemRepresentation:patchFilePath maxLength:sizeof(patchFilePath) - 1]) {
        _error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to open header and represent as a file system representation: %@", _patchFile] }];
        return;
    }
    
    FILE *file = fopen(patchFilePath, "wb");
    if (file == NULL) {
        _error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to open patch file for writing: %@", _patchFile] }];
        return;
    }
    
    _file = file;
    
    char magic[] = SPARKLE_DELTA_FORMAT_MAGIC;
    if (fwrite(magic, sizeof(magic) - 1, 1, file) < 1) {
        _error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: @"Failed to write magic value due to io error" }];
        return;
    }
    
    SPUDeltaCompressionMode compression = (header.compression == SPUDeltaCompressionModeDefault) ? SPUDeltaCompressionModeLZMA : header.compression;
    
    _compression = compression;
    
    if (fwrite(&compression, sizeof(compression), 1, file) < 1) {
        _error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: @"Failed to write compression value due to io error" }];
        return;
    }
    
    // We only support configuring compression level for bzip2
    uint8_t compressionLevel = 0;
    switch (compression) {
        case SPUDeltaCompressionModeBzip2:
#if SPARKLE_BUILD_BZIP2_DELTA_SUPPORT
            // Only 1 - 9 are valid, 0 is a special case for using default 9
            if (header.compressionLevel <= 0 || header.compressionLevel > 9) {
                compressionLevel = 9;
            } else {
                compressionLevel = header.compressionLevel;
            }
            
            break;
#else
            _error = [NSError errorWithDomain:SPARKLE_BZIP2_ERROR_DOMAIN code:-1 userInfo:@{ NSLocalizedDescriptionKey: @"Failed to write bzip2 patch because bzip2 support is disabled" }];
            return;
#endif
        // Some supported formats below have a documented level even though it's not customizable
        // Let's record them in the archive
        case SPUDeltaCompressionModeLZMA:
            compressionLevel = 6;
            break;
        case SPUDeltaCompressionModeZLIB:
            compressionLevel = 5;
            break;
        // These formats don't have any documented level or aren't applicable
        case SPUDeltaCompressionModeLZ4:
        case SPUDeltaCompressionModeLZFSE:
        case SPUDeltaCompressionModeNone:
            compressionLevel = 0;
    }
    
    SparkleDeltaArchiveMetadata metadata = {.compressionLevel = compressionLevel, .fileSystemCompression = header.fileSystemCompression};
    
    if (fwrite(&metadata, sizeof(metadata), 1, file) < 1) {
        _error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: @"Failed to write metadata value due to io error" }];
        return;
    }
    
    switch (compression) {
        case SPUDeltaCompressionModeNone:
            break;
        case SPUDeltaCompressionModeBzip2: {
#if SPARKLE_BUILD_BZIP2_DELTA_SUPPORT
            int bzerror = 0;
            // Compression level can be 1 - 9
            int blockSize100k = (int)compressionLevel;
            
            BZFILE *bzipFile = BZ2_bzWriteOpen(&bzerror, file, blockSize100k, 0, 0);
            if (bzipFile == NULL) {
                switch (bzerror) {
                    case BZ_IO_ERROR:
                        _error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: @"Failed to open bz2 stream for writing due to io error" }];
                        break;
                    default:
                        _error = [NSError errorWithDomain:SPARKLE_BZIP2_ERROR_DOMAIN code:bzerror userInfo:@{ NSLocalizedDescriptionKey: @"Failed to open bz2 stream for writing" }];
                        break;
                }
                
                return;
            }
            
            _bzipFile = bzipFile;
#endif
            
            break;
        }
        case SPUDeltaCompressionModeLZMA:
        case SPUDeltaCompressionModeLZFSE:
        case SPUDeltaCompressionModeLZ4:
        case SPUDeltaCompressionModeZLIB: {
            if (compression_stream_init(&_compressionStream, COMPRESSION_STREAM_ENCODE, compressionAlgorithmForMode(compression)) != COMPRESSION_STATUS_OK) {
                _error = [NSError errorWithDomain:SPARKLE_COMPRESSION_ERROR_DOMAIN code:COMPRESSION_STATUS_ERROR userInfo:@{ NSLocalizedDescriptionKey: @"Failed to open compression stream for writing" }];
                
                return;
            }
            
            _initializedCompressionStream = YES;
            break;
        }
    }
    
    if (![self createBuffers]) {
        return;
    }
    
    uint16_t majorVersion = header.majorVersion;
    [self _writeBuffer:&majorVersion length:sizeof(majorVersion)];
    
    uint16_t minorVersion = header.minorVersion;
    [self _writeBuffer:&minorVersion length:sizeof(minorVersion)];
    
    [self _writeBuffer:header.beforeTreeHash length:BINARY_DELTA_HASH_LENGTH];
    [self _writeBuffer:header.afterTreeHash length:BINARY_DELTA_HASH_LENGTH];
    
    if (majorVersion >= SUBinaryDeltaMajorVersion4) {
        NSDate *bundleCreationDate = header.bundleCreationDate;
        
        // If bundleCreationDate == nil, we will write out a 0 time interval
        double timeInterval = bundleCreationDate.timeIntervalSinceReferenceDate;
        [self _writeBuffer:&timeInterval length:sizeof(timeInterval)];
    }
}

- (void)addItem:(SPUDeltaArchiveItem *)item
{
    [_writableItems addObject:item];
}

- (void)finishEncodingItems
{
    if (_error != nil) {
        return;
    }
    
    NSMutableArray<SPUDeltaArchiveItem *> *writableItems = _writableItems;
    
    // Build relative path table for tracking file clones
    NSMutableDictionary<NSString *, NSNumber *> *relativePathToIndexTable = [NSMutableDictionary dictionary];
    uint32_t currentRelativePathIndex = 0;
    for (SPUDeltaArchiveItem *item in writableItems) {
        NSString *relativePath = item.relativeFilePath;
        assert(relativePath != nil);
        
        relativePathToIndexTable[relativePath] = @(currentRelativePathIndex);
        currentRelativePathIndex++;
    }
    
    // Clone commands reference relative file paths in this table but sometimes there may not
    // be an entry if extraction for an original item was skipped. Fill out any missing file path entries.
    // For example, if A.app has Contents/A and B.app has Contents/A and Contents/B,
    // where A and B's contents are the same and A is the same in both apps, normally we would not record Contents/A because its extraction was skipped. However now B is a clone of A so we need a record for A.
    NSMutableArray<NSString *> *newClonedPathEntries = [NSMutableArray array];
    for (SPUDeltaArchiveItem *item in writableItems) {
        NSString *clonedRelativePath = item.clonedRelativePath;
        
        if (clonedRelativePath != nil && relativePathToIndexTable[clonedRelativePath] == nil) {
            [newClonedPathEntries addObject:clonedRelativePath];
            
            relativePathToIndexTable[clonedRelativePath] = @(currentRelativePathIndex);
            currentRelativePathIndex++;
        }
    }
    
    if (relativePathToIndexTable.count > UINT32_MAX) {
        // Very unlikely but we should guard against this
        // Clones rely on 32-bit indexes
        _error = [NSError errorWithDomain:SPARKLE_DELTA_ARCHIVE_ERROR_DOMAIN code:SPARKLE_DELTA_ARCHIVE_ERROR_CODE_TOO_MANY_FILES userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"There are too many file entries to create a patch for (more than %u)", UINT32_MAX] }];
        return;
    }
    
    // Compute length of path section to write
    uint64_t totalPathLength = 0;
    for (SPUDeltaArchiveItem *item in writableItems) {
        NSString *relativePath = item.relativeFilePath;
        
        char relativePathString[PATH_MAX + 1] = {0};
        if (![relativePath getFileSystemRepresentation:relativePathString maxLength:sizeof(relativePathString) - 1]) {
            _error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Relative path cannot be retrieved and expressed as a file system representation: %@", relativePath] }];
            break;
        }
        
        totalPathLength += strlen(relativePathString) + 1;
    }
    for (NSString *clonedPathEntry in newClonedPathEntries) {
        char relativePathString[PATH_MAX + 1] = {0};
        if (![clonedPathEntry getFileSystemRepresentation:relativePathString maxLength:sizeof(relativePathString) - 1]) {
            _error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Relative path for clone cannot be retrieved and expressed as a file system representation: %@", clonedPathEntry] }];
            break;
        }
        
        totalPathLength += strlen(relativePathString) + 1;
    }
    
    if (_error != nil) {
        return;
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
            _error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Relative path cannot be encoded and expressed as a file system representation: %@", relativePath] }];
            break;
        }
        
        if (![self _writeBuffer:pathBuffer length:(int32_t)strlen(pathBuffer) + 1]) {
            break;
        }
    }
    for (NSString *clonedPathEntry in newClonedPathEntries) {
        char pathBuffer[PATH_MAX + 1] = {0};
        if (![clonedPathEntry getFileSystemRepresentation:pathBuffer maxLength:PATH_MAX]) {
            _error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Relative path for clone cannot be encoded and expressed as a file system representation: %@", clonedPathEntry] }];
            break;
        }
        
        if (![self _writeBuffer:pathBuffer length:(int32_t)strlen(pathBuffer) + 1]) {
            break;
        }
    }
    
    if (_error != nil) {
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
        if ((commands & SPUDeltaItemCommandClone) != 0) {
            // Store any desired file permissions changes for the clone
            // Clones can be binary diffs from other sources too. Since we are creating a
            // new file in that case (rather than a copy) we want to store file mode as well
            if ((commands & SPUDeltaItemCommandModifyPermissions) != 0) {
                NSString *sourcePath = item.sourcePath;
                assert(sourcePath != nil);
                
                char sourcePathString[PATH_MAX + 1] = {0};
                if (![sourcePath getFileSystemRepresentation:sourcePathString maxLength:sizeof(sourcePathString) - 1]) {
                    _error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Path cannot be decoded and expressed as a file system representation while encoding cloned binary diff item: %@", sourcePath] }];
                    break;
                }
                
                struct stat fileInfo = {0};
                if (lstat(sourcePathString, &fileInfo) != 0) {
                    _error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to lstat() on %@", sourcePath] }];
                    break;
                }
                
                uint16_t extractMode = fileInfo.st_mode;
                uint16_t encodedMode;
                if ((commands & SPUDeltaItemCommandModifyPermissions) != 0) {
                    encodedMode = (extractMode & ~PERMISSION_FLAGS) | item.mode;
                } else {
                    encodedMode = extractMode;
                }
                
                item.mode = extractMode;
                
                // Store file mode (including desired permissions)
                if (![self _writeBuffer:&encodedMode length:sizeof(encodedMode)]) {
                    break;
                }
            }
            
            // Store index to relative path table
            NSString *clonedRelativePath = item.clonedRelativePath;
            assert(clonedRelativePath != nil);
            
            NSNumber *relativePathIndex = relativePathToIndexTable[clonedRelativePath];
            if (relativePathIndex == nil) {
                // We have quite a problem here
                _error = [NSError errorWithDomain:SPARKLE_DELTA_ARCHIVE_ERROR_DOMAIN code:SPARKLE_DELTA_ARCHIVE_ERROR_CODE_BAD_CLONE_LOOKUP userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Relative file path index for %@ could not be located", clonedRelativePath] }];
                break;
            }
            
            uint32_t relativePathCIndex = relativePathIndex.unsignedIntValue;
            if (![self _writeBuffer:&relativePathCIndex length:sizeof(relativePathCIndex)]) {
                break;
            }
            
            if ((commands & SPUDeltaItemCommandBinaryDiff) != 0) {
                NSString *itemPath = item.itemFilePath;
                assert(itemPath != nil);
                
                char itemFilePathString[PATH_MAX + 1] = {0};
                if (![itemPath getFileSystemRepresentation:itemFilePathString maxLength:sizeof(itemFilePathString) - 1]) {
                    _error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Path cannot be decoded and expressed as a file system representation while encoding cloned binary diff item: %@", itemPath] }];
                    break;
                }
                
                struct stat fileInfo = {0};
                if (lstat(itemFilePathString, &fileInfo) != 0) {
                    _error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to lstat() on %@", itemPath] }];
                    break;
                }
                
                uint64_t dataLength = (uint64_t)fileInfo.st_size;
                if (![self _writeBuffer:&dataLength length:sizeof(dataLength)]) {
                    break;
                }
                
                item.codedDataLength = dataLength;
            }
        } else if ((commands & SPUDeltaItemCommandExtract) != 0 || (commands & SPUDeltaItemCommandBinaryDiff) != 0) {
            uint16_t extractMode = 0;
            
            if ((commands & SPUDeltaItemCommandExtract) != 0 || (commands & SPUDeltaItemCommandModifyPermissions) != 0) {
                NSString *sourcePath = item.sourcePath;
                assert(sourcePath != nil);
                
                char sourceFilePathString[PATH_MAX + 1] = {0};
                if (![sourcePath getFileSystemRepresentation:sourceFilePathString maxLength:sizeof(sourceFilePathString) - 1]) {
                    _error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Path cannot be decoded and expressed as a file system representation while encoding items: %@", sourcePath] }];
                    break;
                }
                
                struct stat sourceFileInfo = {0};
                if (lstat(sourceFilePathString, &sourceFileInfo) != 0) {
                    _error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to lstat() on %@", sourcePath] }];
                    break;
                }
                
                // For symbolic links we always default to 0755 when adding new items
                // Symbolic link permissions can get more easily lost when moving to other (linux) filesystems,
                // so we only support the macOS default
                if (S_ISLNK(sourceFileInfo.st_mode)) {
                    extractMode = (sourceFileInfo.st_mode & ~PERMISSION_FLAGS) | VALID_SYMBOLIC_LINK_PERMISSIONS;
                } else {
                    extractMode = sourceFileInfo.st_mode;
                }
                
                uint16_t encodedMode;
                if ((commands & SPUDeltaItemCommandModifyPermissions) != 0) {
                    encodedMode = (extractMode & ~PERMISSION_FLAGS) | item.mode;
                } else {
                    encodedMode = extractMode;
                }
                
                item.mode = extractMode;
                
                // Store file mode (including desired permissions)
                if (![self _writeBuffer:&encodedMode length:sizeof(encodedMode)]) {
                    break;
                }
            }
            
            // Store data length
            // Length doesn't matter for directory names (we already track the name in the relative path)
            
            NSString *itemPath = item.itemFilePath;
            assert(itemPath != nil);
            
            char itemFilePathString[PATH_MAX + 1] = {0};
            if (![itemPath getFileSystemRepresentation:itemFilePathString maxLength:sizeof(itemFilePathString) - 1]) {
                _error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Path cannot be decoded and expressed as a file system representation while encoding items: %@", itemPath] }];
                break;
            }
            
            struct stat itemFileInfo = {0};
            if (lstat(itemFilePathString, &itemFileInfo) != 0) {
                _error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to lstat() on %@", itemPath] }];
                break;
            }
            
            if ((commands & SPUDeltaItemCommandBinaryDiff) != 0 || S_ISREG(extractMode)) {
                uint64_t dataLength = (uint64_t)itemFileInfo.st_size;
                if (![self _writeBuffer:&dataLength length:sizeof(dataLength)]) {
                    break;
                }
                
                item.codedDataLength = dataLength;
            } else if (S_ISLNK(extractMode)) {
                off_t fileSize = itemFileInfo.st_size;
                if (fileSize > UINT16_MAX) {
                    _error = [NSError errorWithDomain:SPARKLE_DELTA_ARCHIVE_ERROR_DOMAIN code:SPARKLE_DELTA_ARCHIVE_ERROR_CODE_LINK_TOO_LONG userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Link path has a destination that is too long: %lld bytes", fileSize] }];
                    break;
                }
                
                uint16_t dataLength = (uint16_t)fileSize;
                if (![self _writeBuffer:&dataLength length:sizeof(dataLength)]) {
                    break;
                }
                
                item.codedDataLength = dataLength;
            }
        } else if ((commands & SPUDeltaItemCommandModifyPermissions) != 0) {
            // Store file permissions
            uint16_t mode = item.mode;
            if (![self _writeBuffer:&mode length:sizeof(mode)]) {
                break;
            }
        }
    }
    
    if (_error != nil) {
        return;
    }
    
    // Encode end command marker
    SPUDeltaItemCommands endCommand = SPUDeltaItemCommandEndMarker;
    if (![self _writeBuffer:&endCommand length:sizeof(endCommand)]) {
        return;
    }
    
    // Encode all of our file contents
    void *tempBuffer = _partialChunkBuffer;
    for (SPUDeltaArchiveItem *item in writableItems) {
        SPUDeltaItemCommands commands = item.commands;
        if ((commands & SPUDeltaItemCommandExtract) != 0 || (commands & SPUDeltaItemCommandBinaryDiff) != 0) {
            NSString *itemPath = item.itemFilePath;
            assert(itemPath != nil);
            
            mode_t extractMode = item.mode;
            if ((commands & SPUDeltaItemCommandBinaryDiff) != 0 || S_ISREG(extractMode)) {
                // Write out file contents to archive in chunks
                
                uint64_t totalItemSize = item.codedDataLength;
                if (totalItemSize > 0) {
                    char itemFilePathString[PATH_MAX + 1] = {0};
                    if (![itemPath getFileSystemRepresentation:itemFilePathString maxLength:sizeof(itemFilePathString) - 1]) {
                        _error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Path to finish encoding cannot be decoded and expressed as a file system representation: %@", itemPath] }];
                        break;
                    }
                    
                    FILE *inputFile = fopen(itemFilePathString, "rb");
                    if (inputFile == NULL) {
                        _error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to open file for reading while encoding items: %@", itemPath] }];
                        break;
                    }
                    
                    uint64_t bytesLeftoverToCopy = totalItemSize;
                    while (bytesLeftoverToCopy > 0) {
                        uint64_t currentBlockSize = (bytesLeftoverToCopy >= PARTIAL_IO_CHUNK_SIZE) ? PARTIAL_IO_CHUNK_SIZE : bytesLeftoverToCopy;
                        
                        if (fread(tempBuffer, currentBlockSize, 1, inputFile) < 1) {
                            _error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to read %llu chunk bytes while encoding items", currentBlockSize] }];
                            break;
                        }
                        
                        if (![self _writeBuffer:tempBuffer length:(int32_t)currentBlockSize]) {
                            break;
                        }
                        
                        bytesLeftoverToCopy -= currentBlockSize;
                    }
                    
                    fclose(inputFile);
                    
                    if (_error != nil) {
                        break;
                    }
                }
            } else if (S_ISLNK(extractMode)) {
                char itemFilePathString[PATH_MAX + 1] = {0};
                if (![itemPath getFileSystemRepresentation:itemFilePathString maxLength:sizeof(itemFilePathString) - 1]) {
                    _error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Link path to finish encoding cannot be decoded and expressed as a file system representation: %@", itemPath] }];
                    break;
                }
                
                char linkDestination[PATH_MAX + 1] = {0};
                ssize_t linkDestinationLength = readlink(itemFilePathString, linkDestination, PATH_MAX);
                if (linkDestinationLength < 0) {
                    _error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to readlink() file at %@", itemPath] }];
                    break;
                }
                
                if (![self _writeBuffer:linkDestination length:(int32_t)strlen(linkDestination)]) {
                    break;
                }
            }
        }
    }
    
    // Close up and write final data to compressed streams
    
#if SPARKLE_BUILD_BZIP2_DELTA_SUPPORT
    if (_bzipFile != NULL) {
        int bzerror = 0;
        BZ2_bzWriteClose64(&bzerror, _bzipFile, 0, NULL, NULL, NULL, NULL);
        if (bzerror == BZ_IO_ERROR) {
            _error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: @"Failed to write and close bzip2 file due to IO error" }];
            return;
        }
    } else
#endif
    if (_initializedCompressionStream) {
        void *compressionBuffer = _compressionBuffer;
        FILE *file = _file;
        
        _compressionStream.src_size = 0;
        
        while (_compressionStream.dst_size > 0) {
            _compressionStream.dst_ptr = compressionBuffer;
            _compressionStream.dst_size = COMPRESSION_BUFFER_SIZE;
        
            compression_status status = compression_stream_process(&_compressionStream, COMPRESSION_STREAM_FINALIZE);
            if (status == COMPRESSION_STATUS_ERROR) {
                _error = [NSError errorWithDomain:SPARKLE_COMPRESSION_ERROR_DOMAIN code:COMPRESSION_STATUS_ERROR userInfo:@{ NSLocalizedDescriptionKey: @"Failed to write final bits of Compression based file" }];
                return;
            }
            
            size_t compressedBytesToWrite = (size_t)(_compressionStream.dst_ptr - (uint8_t *)compressionBuffer);
            if (compressedBytesToWrite > 0) {
                if (fwrite(compressionBuffer, compressedBytesToWrite, 1, file) < 1) {
                    _error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: @"Failed to write and close Compression based file due to io error" }];
                    return;
                }
            }
            
            if (status == COMPRESSION_STATUS_END) {
                // We're done
                break;
            }
        }
    }
}

@end
