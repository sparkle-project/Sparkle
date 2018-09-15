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
@synthesize dsaSignature;

static NSData *decode(NSString *str) {
    if (str == nil) {
        return nil;
    }

    NSString *stripped = [str stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return [[NSData alloc] initWithBase64Encoding:stripped];
}

- (instancetype)initWithDsa:(NSString * _Nullable)maybeDsa ed:(NSString * _Nullable)maybeEd25519
{
    self = [super init];
    if (self) {
        if (maybeDsa != nil) {
            self.dsaSignature = decode(maybeDsa);
        }
        if (maybeEd25519 != nil) {
            NSData *data = decode(maybeEd25519);
            assert(64 == sizeof(self->ed25519_signature));
            [data getBytes:self->ed25519_signature length:sizeof(self->ed25519_signature)];
        }
    }
    return self;
}

@end

@implementation SUPublicKeys
@synthesize dsaPubKey;

- (instancetype)initWithDsa:(NSString * _Nullable)maybeDsa ed:(NSString * _Nullable)maybeEd25519
{
    self = [super init];
    if (self) {
        self.dsaPubKey = maybeDsa;
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
    return [thisKey isEqualToString:thatKey];
}

@end
