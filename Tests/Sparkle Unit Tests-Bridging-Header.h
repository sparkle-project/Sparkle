//
//  Use this file to import your target's public headers that you would like to expose to Swift.
//

#import "SUUnarchiver.h"
#import "SUPipedUnarchiver.h"
#import "SUBinaryDeltaCommon.h"
#import "SUFileManager.h"

extern NSString *SUAppleQuarantineIdentifier;

@interface SUFileManager (Private)

- (BOOL)_acquireAuthorizationWithError:(NSError *__autoreleasing *)error;

- (BOOL)_itemExistsAtURL:(NSURL *)fileURL;
- (BOOL)_itemExistsAtURL:(NSURL *)fileURL isDirectory:(BOOL *)isDirectory;

- (BOOL)_makeDirectoryAtURL:(NSURL *)url error:(NSError * __autoreleasing *)error;

@end
