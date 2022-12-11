//
//  SPUInstallationInputData.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/24/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

@class SUSignatures;

NS_ASSUME_NONNULL_BEGIN

__attribute__((objc_direct_members)) @interface SPUInstallationInputData : NSObject <NSSecureCoding>

/*
 * relaunchPath - path to application bundle to relaunch and listen for termination
 * hostBundlePath - path to host bundle to update & replace
 * updateDirectoryPath - path to update directory (i.e, temporary directory containing the new update archive)
 * downloadName - name of update archive in update directory
 * signatures - signatures for the update that came from the appcast item
 * decryptionPassword - optional decryption password for dmg archives
 */
- (instancetype)initWithRelaunchPath:(NSString *)relaunchPath hostBundlePath:(NSString *)hostBundlePath updateDirectoryPath:(NSString *)updateDirectoryPath downloadName:(NSString *)downloadName installationType:(NSString *)installationType signatures:(SUSignatures * _Nullable)signatures decryptionPassword:(nullable NSString *)decryptionPassword;

@property (nonatomic, copy, readonly) NSString *relaunchPath;
@property (nonatomic, copy, readonly) NSString *hostBundlePath;
@property (nonatomic, copy, readonly) NSString *updateDirectoryPath;
@property (nonatomic, copy, readonly) NSString *downloadName;
@property (nonatomic, copy, readonly) NSString *installationType;
@property (nonatomic, readonly, nullable) SUSignatures *signatures; // nullable because although not using signatures is deprecated, it's still supported
@property (nonatomic, copy, readonly, nullable) NSString *decryptionPassword;

@end

NS_ASSUME_NONNULL_END
