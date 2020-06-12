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

@interface SUSignatures : NSObject <NSSecureCoding> {
    unsigned char ed25519_signature[64];
    bool has_ed25519_signature;
}
@property (strong, readonly, nullable) NSData *dsaSignature;
@property (readonly, nullable, nonatomic) const unsigned char *ed25519Signature;

- (instancetype)initWithDsa:(NSString * _Nullable)dsa ed:(NSString * _Nullable)ed;
@end


@interface SUPublicKeys : NSObject {
    unsigned char ed25519_public_key[32];
    bool has_ed25519_public_key;
}
@property (strong, readonly, nullable) NSString *dsaPubKey;
@property (readonly, nullable, nonatomic) const unsigned char *ed25519PubKey;

- (instancetype)initWithDsa:(NSString * _Nullable)dsa ed:(NSString * _Nullable)ed;

@end

NS_ASSUME_NONNULL_END
