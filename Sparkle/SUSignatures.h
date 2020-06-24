//
//  SUSignatures.h
//  Sparkle
//
//  Created by Kornel on 15/09/2018.
//  Copyright © 2018 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

#if __MAC_OS_X_VERSION_MAX_ALLOWED < 1090
@interface NSData (SUSignatureVerifier)
- (id)initWithBase64Encoding:(NSString *)base64String;
@end
#endif

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(uint8_t, SUSigningInputStatus) {
    /// An input was not provided at all.
    SUSigningInputStatusAbsent = 0,

    /// An input was provided, but did not have the correct format.
    SUSigningInputStatusInvalid,

    /// An input was provided and can be used for verifying signing information.
    SUSigningInputStatusPresent,
    SUSigningInputStatusLastValidCase = SUSigningInputStatusPresent
};

@interface SUSignatures : NSObject <NSSecureCoding> {
    unsigned char ed25519_signature[64];
}
@property (strong, readonly, nullable) NSData *dsaSignature;
@property (readonly) SUSigningInputStatus dsaSignatureStatus;

@property (readonly, nullable, nonatomic) const unsigned char *ed25519Signature;
@property (readonly) SUSigningInputStatus ed25519SignatureStatus;

- (instancetype)initWithDsa:(NSString * _Nullable)dsa ed:(NSString * _Nullable)ed;
@end


@interface SUPublicKeys : NSObject {
    unsigned char ed25519_public_key[32];
}
@property (strong, readonly, nullable) NSString *dsaPubKey;
@property (readonly) SUSigningInputStatus dsaPubKeyStatus;

@property (readonly, nullable, nonatomic) const unsigned char *ed25519PubKey;
@property (readonly) SUSigningInputStatus ed25519PubKeyStatus;

/// Returns YES if either key is present (though they may be invalid).
@property (readonly) BOOL hasAnyKeys;

- (instancetype)initWithDsa:(NSString * _Nullable)dsa ed:(NSString * _Nullable)ed;

@end

NS_ASSUME_NONNULL_END
