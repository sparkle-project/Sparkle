//
//  SUSignatures.m
//  Sparkle
//
//  Created by Kornel on 15/09/2018.
//  Copyright © 2018 Sparkle Project. All rights reserved.
//

#import "SUSignatures.h"
#import <assert.h>

@implementation SUSignatures
@synthesize dsaSignature;

static NSData *decode(NSString *str) {
    NSString *stripped = [str stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (@available(macOS 10.9, *)) {
        return [[NSData alloc] initWithBase64EncodedString:stripped options:0];
    } else {
        return [[NSData alloc] initWithBase64Encoding:stripped];
    }
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
