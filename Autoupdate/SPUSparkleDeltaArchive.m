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


#include "AppKitPrevention.h"

#define SPARKLE_FORMAT_MAGIC "spk!"

#define PERMISSION_FLAGS (S_IRWXU | S_IRWXG | S_IRWXO | S_ISUID | S_ISGID | S_ISVTX)

typedef NS_ENUM(uint8_t, SPUDeltaCompressionMode) {
    SPUDeltaCompressionModeNone = 0,
    SPUDeltaCompressionModeBzip2 = 1
};

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

- (nullable instancetype)initWithPatchFileForWriting:(NSString *)patchFile
{
    self = [super init];
    if (self != nil) {
        FILE *file = fopen(patchFile.fileSystemRepresentation, "wb");
        if (file == NULL) {
            NSLog(@"Failed to open for writing binary");
            return nil;
        }
        
        char magic[] = SPARKLE_FORMAT_MAGIC;
        if (fwrite(magic, sizeof(magic) - 1, 1, file) < 1) {
            NSLog(@"Failed to write magic");
            fclose(file);
            return nil;
        }
        
        SPUDeltaCompressionMode compression = SPUDeltaCompressionModeBzip2;
        // Only one of the bytes is used, but we supply 3 more for alignment purposes
        uint32_t compressionData = compression;
        if (fwrite(&compressionData, sizeof(compressionData), 1, file) < 1) {
            NSLog(@"Failed to write compression");
            fclose(file);
            return nil;
        }
        
        if (compressionData == SPUDeltaCompressionModeBzip2) {
            int bzerror = 0;
            int blockSize100k = 9; // Can be 1 - 9
            
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
        
        if (strncmp(magic, SPARKLE_FORMAT_MAGIC, sizeof(magic) - 1) != 0) {
            fclose(_file);
            return nil;
        }
        
        uint32_t compressionData = 0;
        if (fread(&compressionData, sizeof(compressionData), 1, _file) < 1) {
            fclose(_file);
            return nil;
        }
        
        SPUDeltaCompressionMode compression = (SPUDeltaCompressionMode)compressionData;
        
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

- (BOOL)_readBuffer:(void *)buffer length:(size_t)length
{
    if (self.errorDetected) {
        return NO;
    }
    
    switch (self.compression) {
        case SPUDeltaCompressionModeNone: {
            if (fread(buffer, length, 1, self.file) < 1) {
                self.errorDetected = YES;
                return NO;
            } else {
                return YES;
            }
        }
        case SPUDeltaCompressionModeBzip2: {
            int bzerror = 0;
            int bytesRead = BZ2_bzRead(&bzerror, self.bzipFile, buffer, (int)length);
            
            switch (bzerror) {
                case BZ_OK:
                case BZ_STREAM_END:
                    if ((size_t)bytesRead < length) {
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
    
    if (![self _readBuffer:fileTableData length:filePathSectionSize]) {
        free(fileTableData);
        return nil;
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
            SPUDeltaFileAttributes attributes = 0;
            if (![self _readBuffer:&attributes length:sizeof(attributes)]) {
                break;
            }
            
            // Test if we've reached the end marker
            if (attributes == 0) {
                break;
            }
            
            // Check if we need to decode additional data
            uint16_t decodedMode = 0;
            uint64_t decodedDataLength = 0;
            
            if ((attributes & SPUDeltaFileAttributesExtract) != 0 || (attributes & SPUDeltaFileAttributesBinaryDiff) != 0) {
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
            } else if ((attributes & SPUDeltaFileAttributesModifyPermissions) != 0) {
                // Decode file permissions
                if (![self _readBuffer:&decodedMode length:sizeof(decodedMode)]) {
                    break;
                }
            }
            
            SPUDeltaArchiveItem *archiveItem = [[SPUDeltaArchiveItem alloc] initWithRelativeFilePath:relativeFilePaths[currentItemIndex] attributes:attributes permissions:decodedMode];
            
            archiveItem.decodedDataLength = decodedDataLength;
            
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
    
    SPUDeltaFileAttributes attributes = item.attributes;
    assert((attributes & SPUDeltaFileAttributesExtract) != 0 || (attributes & SPUDeltaFileAttributesBinaryDiff) != 0);
    
    uint16_t mode = item.permissions;
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ((attributes & SPUDeltaFileAttributesBinaryDiff) != 0 || S_ISREG(mode) || S_ISLNK(mode)) {
        // Handle regular files
        // Binary diffs are always on regular files only
        
        uint64_t decodedLength = item.decodedDataLength;
        
        void *buffer;
        if (decodedLength == 0) {
            // Skip over files with empty data
            buffer = NULL;
        } else {
            buffer = calloc(1, decodedLength);
            if (buffer == NULL) {
                self.errorDetected = YES;
                return NO;
            }
            
            if (![self _readBuffer:buffer length:decodedLength]) {
                return NO;
            }
        }
        
        if ((attributes & SPUDeltaFileAttributesBinaryDiff) != 0 || S_ISREG(mode)) {
            // Regular files
            NSData *data = (decodedLength > 0) ? [NSData dataWithBytesNoCopy:buffer length:decodedLength] : [NSData data];
            if (data == nil) {
                self.errorDetected = YES;
                free(buffer);
                return NO;
            }
            
            BOOL writeSuccess = [data writeToFile:physicalFilePath atomically:NO];
            if (!writeSuccess) {
                self.errorDetected = YES;
                return NO;
            }
            
            if (chmod(physicalFilePath.fileSystemRepresentation, mode) != 0) {
                self.errorDetected = YES;
                return NO;
            }
        } else {
            // Link files
            NSString *destinationPath = (decodedLength > 0) ? [fileManager stringWithFileSystemRepresentation:buffer length:decodedLength] : @"";
            if (destinationPath == nil) {
                self.errorDetected = YES;
                return NO;
            }
            
            free(buffer);
            
            NSError *error = nil;
            if (![fileManager createSymbolicLinkAtPath:physicalFilePath withDestinationPath:destinationPath error:&error]) {
                self.errorDetected = YES;
                return NO;
            }
            
            // We shouldn't fail if setting permissions on symlinks fail
            // Symbolic link permissions are weird
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

- (BOOL)_writeBuffer:(void *)buffer length:(size_t)length
{
    if (self.errorDetected) {
        return NO;
    }
    
    switch (self.compression) {
        case SPUDeltaCompressionModeNone: {
            BOOL success = (fwrite(buffer, length, 1, self.file) == 1);
            if (!success) {
                self.errorDetected = YES;
            }
            
            return success;
        }
        case SPUDeltaCompressionModeBzip2: {
            int bzerror = 0;
            BZ2_bzWrite(&bzerror, self.bzipFile, buffer, (int)length);
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
    
    // Write all of the relative path lengths
    for (SPUDeltaArchiveItem *item in writableItems) {
        NSString *relativePath = item.relativeFilePath;
        const char *relativePathString = relativePath.UTF8String;
        char pathBuffer[PATH_MAX + 1] = {0};
        strncpy(pathBuffer, relativePathString, PATH_MAX);
        
        if (![self _writeBuffer:pathBuffer length:strlen(pathBuffer) + 1]) {
            break;
        }
    }
    
    if (self.errorDetected) {
        return;
    }
    
    // Encode the items
    for (SPUDeltaArchiveItem *item in writableItems) {
        // Store attributes
        SPUDeltaFileAttributes attributes = item.attributes;
        if (![self _writeBuffer:&attributes length:sizeof(attributes)]) {
            break;
        }
        
        // Check if we need to encode additional data
        if ((attributes & SPUDeltaFileAttributesExtract) != 0 || (attributes & SPUDeltaFileAttributesBinaryDiff) != 0) {
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
            if ((attributes & SPUDeltaFileAttributesModifyPermissions) != 0) {
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
            }
        } else if ((attributes & SPUDeltaFileAttributesModifyPermissions) != 0) {
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
    SPUDeltaFileAttributes endAttributes = 0;
    if (![self _writeBuffer:&endAttributes length:sizeof(endAttributes)]) {
        return;
    }
    
    // Encode all of our file contents
    for (SPUDeltaArchiveItem *item in writableItems) {
        SPUDeltaFileAttributes attributes = item.attributes;
        if ((attributes & SPUDeltaFileAttributesExtract) != 0 || (attributes & SPUDeltaFileAttributesBinaryDiff) != 0) {
            NSString *physicalPath = item.physicalFilePath;
            assert(physicalPath != nil);
            
            mode_t originalMode = item.originalMode;
            if (S_ISREG(originalMode)) {
                NSURL *physicalURL = [NSURL fileURLWithPath:physicalPath isDirectory:NO];
                NSMutableData *contents = [NSMutableData dataWithContentsOfURL:physicalURL];
                if (contents == nil) {
                    self.errorDetected = YES;
                    break;
                }
                
                if (![self _writeBuffer:contents.mutableBytes length:contents.length]) {
                    break;
                }
            } else if (S_ISLNK(originalMode)) {
                char linkDestination[PATH_MAX + 1] = {0};
                ssize_t linkDestinationLength = readlink(physicalPath.fileSystemRepresentation, linkDestination, PATH_MAX);
                if (linkDestinationLength < 0) {
                    self.errorDetected = YES;
                    break;
                }
                
                if (![self _writeBuffer:linkDestination length:strlen(linkDestination)]) {
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
