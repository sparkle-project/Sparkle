//
//  Use this file to import your target's public headers that you would like to expose to Swift.
//

#import "SUUnarchiver.h"
#import "SUBinaryDeltaUnarchiver.h"
#import "SUPipedUnarchiver.h"
#import "SUBinaryDeltaCommon.h"
#import "SUFileManager.h"
#import "SUAppcast.h"
#import "SUAppcastItem.h"
#import "SUBasicUpdateDriver.h"
#import "SUVersionComparisonProtocol.h"
#import "SUStandardVersionComparator.h"

NS_ASSUME_NONNULL_BEGIN

// Duplicated to avoid exporting a private symbol from SUFileManager
static const char *SUAppleQuarantineIdentifier = "com.apple.quarantine";

@interface SUFileManager (Private)

- (BOOL)_acquireAuthorizationWithError:(NSError *_Nullable __autoreleasing *_Nullable)error;

- (BOOL)_itemExistsAtURL:(NSURL *)fileURL;
- (BOOL)_itemExistsAtURL:(NSURL *)fileURL isDirectory:(nullable BOOL *)isDirectory;

@end

@interface SUBasicUpdateDriver (Private)

+ (SUAppcastItem *)bestItemFromAppcastItems:(NSArray *)appcastItems getDeltaItem:(SUAppcastItem *_Nullable __autoreleasing *_Nullable)deltaItem withHostVersion:(NSString *)hostVersion comparator:(id<SUVersionComparison>)comparator;

@end


@interface SUAppcast (Private)
- (nullable NSArray *)parseAppcastItemsFromXMLFile:(NSURL *)appcastFile error:(NSError *_Nullable __autoreleasing *_Nullable)errorp;
@end

@interface SUBinaryDeltaUnarchiver (Private)

+ (void)updateSpotlightImportersAtBundlePath:(NSString *)targetPath;

NS_ASSUME_NONNULL_END
@end
