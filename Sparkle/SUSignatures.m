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

@implementation SUSignatures
@synthesize dsaSignature = _dsaSignature;

static NSData *decode(NSString *str) {
    if (str == nil) {
        return nil;
    }

    NSString *stripped = [str stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return [[NSData alloc] initWithBase64EncodedString:stripped options:0];
}

- (instancetype)initWithDsa:(NSString * _Nullable)maybeDsa ed:(NSString * _Nullable)maybeEd25519
{
    self = [super init];
    if (self) {
        if (maybeDsa != nil) {
            _dsaSignature = decode(maybeDsa);
        }
        if (maybeEd25519 != nil) {
            NSData *data = decode(maybeEd25519);
            assert(64 == sizeof(self->ed25519_signature));
            [data getBytes:self->ed25519_signature length:sizeof(self->ed25519_signature)];
        }
    }
    return self;
}

- (const unsigned char *)ed25519Signature {
// Xcode may enable this in pedantic mode
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdirect-ivar-access"
    for(size_t i=0; i < sizeof(self->ed25519_signature); i++) {
        if (self->ed25519_signature[i] != 0) {
            return self->ed25519_signature;
        }
    }
    return NULL;
#pragma clang diagnostic pop
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
            NSData *ed = decode(maybeEd25519);
            assert(32 == sizeof(self->ed25519_public_key));
            [ed getBytes:self->ed25519_public_key length:sizeof(self->ed25519_public_key)];
        }
    }
    return self;
}

- (BOOL) isEqualToKey:(SUPublicKeys *)key {
    NSString *thisKey = self.dsaPubKey;
    NSString *thatKey = key.dsaPubKey;
    if (thisKey == nil || thatKey == nil) {
        return NO;
    }
    return NO;
}


- (const unsigned char *)ed25519PubKey {
// Xcode may enable this in pedantic mode
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdirect-ivar-access"
    for(size_t i=0; i < sizeof(self->ed25519_public_key); i++) {
        if (self->ed25519_public_key[i] != 0) {
            return self->ed25519_public_key;
        }
    }
    return NULL;
#pragma clang diagnostic pop
}

@end
