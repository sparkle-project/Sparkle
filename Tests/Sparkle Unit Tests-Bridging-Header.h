//
//  Use this file to import your target's public headers that you would like to expose to Swift.
//

#import "SUUnarchiver.h"
#import "SUUnarchiverProtocol.h"
#import "SUBinaryDeltaUnarchiver.h"
#import "SUPipedUnarchiver.h"
#import "SUBinaryDeltaCommon.h"
#import "SUFileManager.h"
#import "SUExport.h"
#import "SUAppcast.h"
#import "SUAppcast+Private.h"
#import "SUAppcastItem.h"
#import "SUAppcastDriver.h"
#import "SUVersionComparisonProtocol.h"
#import "SUStandardVersionComparator.h"
#import "SUUpdateValidator.h"
#import "SUHost.h"
#import "SPUSkippedUpdate.h"
#import "SUSignatures.h"
#import "SPUInstallationType.h"
#import "SPUAppcastItemStateResolver.h"

NS_ASSUME_NONNULL_BEGIN

// Duplicated to avoid exporting a private symbol from SUFileManager
static const char *SUAppleQuarantineIdentifier = "com.apple.quarantine";

@interface SUFileManager (Private)

- (BOOL)_itemExistsAtURL:(NSURL *)fileURL __attribute__((objc_direct));
- (BOOL)_itemExistsAtURL:(NSURL *)fileURL isDirectory:(nullable BOOL *)isDirectory __attribute__((objc_direct));

@end

@interface SUAppcastDriver (Private)

+ (SUAppcastItem *)bestItemFromAppcastItems:(NSArray *)appcastItems getDeltaItem:(SUAppcastItem *_Nullable __autoreleasing *_Nullable)deltaItem withHostVersion:(NSString *)hostVersion comparator:(id<SUVersionComparison>)comparator __attribute__((objc_direct));

+ (SUAppcast *)filterSupportedAppcast:(SUAppcast *)appcast phasedUpdateGroup:(NSNumber * _Nullable)phasedUpdateGroup skippedUpdate:(SPUSkippedUpdate * _Nullable)skippedUpdate currentDate:(NSDate *)currentDate hostVersion:(NSString *)hostVersion versionComparator:(id<SUVersionComparison>)versionComparator testOSVersion:(BOOL)testOSVersion testMinimumAutoupdateVersion:(BOOL)testMinimumAutoupdateVersion __attribute__((objc_direct));

+ (SUAppcast *)filterAppcast:(SUAppcast *)appcast forMacOSAndAllowedChannels:(NSSet<NSString *> *)allowedChannels __attribute__((objc_direct));

@end

@interface SUBinaryDeltaUnarchiver (Private)

+ (void)updateSpotlightImportersAtBundlePath:(NSString *)targetPath __attribute__((objc_direct));

@end

NS_ASSUME_NONNULL_END
