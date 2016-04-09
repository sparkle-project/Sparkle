//
//  SUInstallationInputData.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/24/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SUInstallationInputData : NSObject <NSSecureCoding>

- (instancetype)initWithRelaunchPath:(NSString *)relaunchPath progressToolPath:(nullable NSString *)progressToolPath hostBundlePath:(NSString *)hostBundlePath updateDirectoryPath:(NSString *)updateDirectoryPath downloadPath:(NSString *)downloadPath dsaSignature:(NSString *)dsaSignature decryptionPassword:(nullable NSString *)decryptionPassword;

@property (nonatomic, copy, readonly) NSString *relaunchPath;
@property (nonatomic, copy, readonly, nullable) NSString *progressToolPath;
@property (nonatomic, copy, readonly) NSString *hostBundlePath;
@property (nonatomic, copy, readonly) NSString *updateDirectoryPath;
@property (nonatomic, copy, readonly) NSString *downloadPath;
@property (nonatomic, copy, readonly) NSString *dsaSignature;
@property (nonatomic, copy, readonly, nullable) NSString *decryptionPassword;

@end

NS_ASSUME_NONNULL_END
