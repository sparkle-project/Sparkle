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

/*
 * relaunchPath - path to application bundle to relaunch and listen for termination
 * hostBundlePath - path to host bundle to update & replace
 * updateDirectoryPath - path to update directory (i.e, temporary directory containing the new update archive)
 * downloadName - name of update archive in update directory
 * dsaSignature - DSA signature for the update that came from the appcast item
 * decryptionPassword - optional decryption password for dmg archives
 */
- (instancetype)initWithRelaunchPath:(NSString *)relaunchPath hostBundlePath:(NSString *)hostBundlePath updateDirectoryPath:(NSString *)updateDirectoryPath downloadName:(NSString *)downloadName dsaSignature:(NSString *)dsaSignature decryptionPassword:(nullable NSString *)decryptionPassword;

@property (nonatomic, copy, readonly) NSString *relaunchPath;
@property (nonatomic, copy, readonly) NSString *hostBundlePath;
@property (nonatomic, copy, readonly) NSString *updateDirectoryPath;
@property (nonatomic, copy, readonly) NSString *downloadName;
@property (nonatomic, copy, readonly) NSString *dsaSignature;
@property (nonatomic, copy, readonly, nullable) NSString *decryptionPassword;

@end

NS_ASSUME_NONNULL_END
