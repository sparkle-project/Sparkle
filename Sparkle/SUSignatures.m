//
//  SUSignatures.m
//  Sparkle
//
//  Created by Kornel on 15/09/2018.
//  Copyright © 2018 Sparkle Project. All rights reserved.
//

#import "SUSignatures.h"
#import <assert.h>
#import "SULog.h"

static NSString *SUDSASignatureKey = @"SUDSASignature";
static NSString *SUEDSignatureKey = @"SUEDSignature";

@implementation SUSignatures
@synthesize dsaSignature = _dsaSignature;

static NSData *decode(NSString *str) {
    if (str == nil) {
        return nil;
    }

    NSString *stripped = [str stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSData *result = [[NSData alloc] initWithBase64EncodedString:stripped options:0];
    if (!result) {
        return [NSData data]; // Distinguish an absent string from a present-but-invalid one.
    }
    return result;
}

- (instancetype)initWithDsa:(NSString * _Nullable)maybeDsa ed:(NSString * _Nullable)maybeEd25519
{
    self = [super init];
    if (self) {
        if (maybeDsa != nil) {
            _dsaSignature = decode(maybeDsa);
        }
        if (maybeEd25519 != nil) {
            self->has_ed25519_signature = true;
            NSData *data = decode(maybeEd25519);
            assert(64 == sizeof(self->ed25519_signature));
            if ([data length] == sizeof(self->ed25519_signature)) {
                [data getBytes:self->ed25519_signature length:sizeof(self->ed25519_signature)];
            } else {
                // A valid Ed25519 signature never has the top bits set in the final byte.
                memset(self->ed25519_signature, -1, sizeof(self->ed25519_signature));
            }
        }
    }
    return self;
}

- (const unsigned char *)ed25519Signature {
// Xcode may enable this in pedantic mode
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdirect-ivar-access"
    if (self->has_ed25519_signature) {
        return self->ed25519_signature;
    }
    return NULL;
#pragma clang diagnostic pop
}

- (instancetype)initWithCoder:(NSCoder *)decoder
{
    self = [super init];
    if (self) {
        NSData *dsaSignature = [decoder decodeObjectOfClass:[NSData class] forKey:SUDSASignatureKey];
        if (dsaSignature) {
            _dsaSignature = dsaSignature;
        }

        NSData *edSignature = [decoder decodeObjectOfClass:[NSData class] forKey:SUEDSignatureKey];
        if (edSignature) {
            if (edSignature.length != sizeof(self->ed25519_signature)) {
                return nil;
            }
            [edSignature getBytes:self->ed25519_signature];
            self->has_ed25519_signature = true;
        }
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    if (self.dsaSignature) {
        [coder encodeObject:self.dsaSignature forKey:SUDSASignatureKey];
    }
    if (self.ed25519Signature) {
// Xcode may enable this in pedantic mode
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdirect-ivar-access"
        NSData *edSignature = [NSData dataWithBytesNoCopy:&self->ed25519_signature length:sizeof(self->ed25519_signature) freeWhenDone:false];
#pragma clang diagnostic pop
        [coder encodeObject:edSignature forKey:SUEDSignatureKey];
    }
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

@end

@implementation SUPublicKeys
@synthesize dsaPubKey = _dsaPubKey;

- (instancetype)initWithDsa:(NSString * _Nullable)maybeDsa ed:(NSString * _Nullable)maybeEd25519
{
    self = [super init];
    if (self) {
        _dsaPubKey = maybeDsa;
        if (maybeEd25519 != nil) {
            self->has_ed25519_public_key = true;
            NSData *ed = decode(maybeEd25519);
            assert(32 == sizeof(self->ed25519_public_key));
            if ([ed length] == sizeof(self->ed25519_public_key)) {
                [ed getBytes:self->ed25519_public_key length:sizeof(self->ed25519_public_key)];
            } else {
                // The stored value will be all zeros.
                // If that /is/ someone's public key, validation will succeed even though they put in an invalid value.
                // This is not a security vulnerability since the public key is embedded in the app,
                // rather than being controlled by a remote attacker.
            }
        }
    }
    return self;
}


- (const unsigned char *)ed25519PubKey {
// Xcode may enable this in pedantic mode
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdirect-ivar-access"
    if (self->has_ed25519_public_key) {
        return self->ed25519_public_key;
    }
    return NULL;
#pragma clang diagnostic pop
}

@end
