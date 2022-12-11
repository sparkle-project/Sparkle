//
//  SUSignatures.h
//  Sparkle
//
//  Created by Kornel on 15/09/2018.
//  Copyright © 2018 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

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
    unsigned char _ed25519_signature[64];
}
@property (nonatomic, readonly, nullable, direct) NSData *dsaSignature;
@property (nonatomic, readonly, direct) SUSigningInputStatus dsaSignatureStatus;

@property (nonatomic, readonly, nullable, direct) const unsigned char *ed25519Signature;
@property (nonatomic, readonly, direct) SUSigningInputStatus ed25519SignatureStatus;

- (instancetype)initWithDsa:(NSString * _Nullable)dsa ed:(NSString * _Nullable)ed __attribute__((objc_direct));
@end


@interface SUPublicKeys : NSObject {
    unsigned char _ed25519_public_key[32];
}
@property (nonatomic, readonly, nullable, direct) NSString *dsaPubKey;
@property (nonatomic, readonly, direct) SUSigningInputStatus dsaPubKeyStatus;

@property (nonatomic, readonly, nullable, direct) const unsigned char *ed25519PubKey;
@property (nonatomic, readonly, direct) SUSigningInputStatus ed25519PubKeyStatus;

/// Returns YES if either key is present (though they may be invalid).
@property (nonatomic, readonly, direct) BOOL hasAnyKeys;

- (instancetype)initWithDsa:(NSString * _Nullable)dsa ed:(NSString * _Nullable)ed __attribute__((objc_direct));

@end

NS_ASSUME_NONNULL_END
