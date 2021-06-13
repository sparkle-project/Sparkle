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


#include "AppKitPrevention.h"

static NSString *SUDSASignatureKey = @"SUDSASignature";
static NSString *SUDSASignatureStatusKey = @"SUDSASignatureStatus";
static NSString *SUEDSignatureKey = @"SUEDSignature";
static NSString *SUEDSignatureStatusKey = @"SUEDSignatureStatus";

@implementation SUSignatures
@synthesize dsaSignature = _dsaSignature;
@synthesize dsaSignatureStatus = _dsaSignatureStatus;
@synthesize ed25519SignatureStatus = _ed25519SignatureStatus;

static SUSigningInputStatus decode(NSString *str, NSData * __strong *outData) {
    if (str == nil) {
        return SUSigningInputStatusAbsent;
    }

    NSString *stripped = [str stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSData *result = [[NSData alloc] initWithBase64EncodedString:stripped options:0];
    if (!result) {
        return SUSigningInputStatusInvalid;
    }
    *outData = result;
    return SUSigningInputStatusPresent;
}

- (instancetype)initWithDsa:(NSString * _Nullable)maybeDsa ed:(NSString * _Nullable)maybeEd25519
{
    self = [super init];
    if (self) {
        _dsaSignatureStatus = decode(maybeDsa, &_dsaSignature);
        if (_dsaSignatureStatus == SUSigningInputStatusInvalid) {
            SULog(SULogLevelError, @"The provided DSA signature could not be decoded.");
        }

        if (maybeEd25519 != nil) {
            NSData *data = nil;
            _ed25519SignatureStatus = decode(maybeEd25519, &data);
            if (data) {
                assert(64 == sizeof(self->ed25519_signature));
                if ([data length] == sizeof(self->ed25519_signature)) {
                    [data getBytes:self->ed25519_signature length:sizeof(self->ed25519_signature)];
                } else {
                    _ed25519SignatureStatus = SUSigningInputStatusInvalid;
                }
            }

            if (_ed25519SignatureStatus == SUSigningInputStatusInvalid) {
                SULog(SULogLevelError, @"The provided EdDSA signature could not be decoded.");
            }
        }
    }
    return self;
}

- (const unsigned char *)ed25519Signature {
// Xcode may enable this in pedantic mode
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdirect-ivar-access"
    if (self.ed25519SignatureStatus == SUSigningInputStatusPresent) {
        return self->ed25519_signature;
    }
    return NULL;
#pragma clang diagnostic pop
}

static BOOL decodeStatus(NSCoder *decoder, NSString *key, SUSigningInputStatus *outStatus) {
    NSInteger rawValue = [decoder decodeIntegerForKey:key];
    if (rawValue > SUSigningInputStatusLastValidCase) {
        return NO;
    }
    *outStatus = (SUSigningInputStatus)rawValue;
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)decoder
{
    self = [super init];
    if (self) {
        if (!decodeStatus(decoder, SUDSASignatureStatusKey, &_dsaSignatureStatus)) {
            return nil;
        }

        NSData *dsaSignature = [decoder decodeObjectOfClass:[NSData class] forKey:SUDSASignatureKey];
        if (dsaSignature) {
            _dsaSignature = dsaSignature;
        }

        if (!decodeStatus(decoder, SUEDSignatureStatusKey, &_ed25519SignatureStatus)) {
            return nil;
        }

        NSData *edSignature = [decoder decodeObjectOfClass:[NSData class] forKey:SUEDSignatureKey];
        if (edSignature) {
            if (edSignature.length != sizeof(self->ed25519_signature)) {
                return nil;
            }
            [edSignature getBytes:self->ed25519_signature length:sizeof(self->ed25519_signature)];
        }
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeInteger:self.dsaSignatureStatus forKey:SUDSASignatureStatusKey];
    if (self.dsaSignature) {
        [coder encodeObject:self.dsaSignature forKey:SUDSASignatureKey];
    }
    [coder encodeInteger:self.ed25519SignatureStatus forKey:SUEDSignatureStatusKey];
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
@synthesize ed25519PubKeyStatus = _ed25519PubKeyStatus;

- (instancetype)initWithDsa:(NSString * _Nullable)maybeDsa ed:(NSString * _Nullable)maybeEd25519
{
    self = [super init];
    if (self) {
        _dsaPubKey = maybeDsa;
        if (maybeEd25519 != nil) {
            NSData *ed = nil;
            _ed25519PubKeyStatus = decode(maybeEd25519, &ed);
            if (ed) {
                assert(32 == sizeof(self->ed25519_public_key));
                if ([ed length] == sizeof(self->ed25519_public_key)) {
                    [ed getBytes:self->ed25519_public_key length:sizeof(self->ed25519_public_key)];
                } else {
                    _ed25519PubKeyStatus = SUSigningInputStatusInvalid;
                }
            }

            if (_ed25519PubKeyStatus == SUSigningInputStatusInvalid) {
                SULog(SULogLevelError, @"The provided EdDSA key could not be decoded.");
            }
        }
    }
    return self;
}

- (SUSigningInputStatus)dsaPubKeyStatus {
    // We don't currently do any prevalidation of DSA public keys,
    // so this is always going to be "present" or "absent".
    return self.dsaPubKey ? SUSigningInputStatusPresent : SUSigningInputStatusAbsent;
}

- (const unsigned char *)ed25519PubKey {
// Xcode may enable this in pedantic mode
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdirect-ivar-access"
    if (self.ed25519PubKeyStatus == SUSigningInputStatusPresent) {
        return self->ed25519_public_key;
    }
    return NULL;
#pragma clang diagnostic pop
}

- (BOOL)hasAnyKeys {
    return self.dsaPubKeyStatus != SUSigningInputStatusAbsent || self.ed25519PubKeyStatus != SUSigningInputStatusAbsent;
}

@end
