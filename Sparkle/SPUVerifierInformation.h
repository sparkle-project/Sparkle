//
//  SPUVerifierInformation.h
//  Autoupdate
//
//  Copyright © 2023 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

SPU_OBJC_DIRECT_MEMBERS @interface SPUVerifierInformation : NSObject

- (instancetype)initWithExpectedVersion:(NSString * _Nullable)expectedVersion expectedContentLength:(uint64_t)expectedContentLength;

@property (nonatomic, readonly, copy, nullable) NSString *expectedVersion;
@property (nonatomic, readonly) uint64_t expectedContentLength;

@property (nonatomic, copy, nullable) NSString *actualVersion;
@property (nonatomic) uint64_t actualContentLength;

@end

NS_ASSUME_NONNULL_END
