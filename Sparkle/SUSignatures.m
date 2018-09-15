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

- (instancetype)initWithDsa:(NSString * _Nullable)maybeDsa ed:(NSString * _Nullable)maybeEd25519
{
    self = [super init];
    if (self) {
        self.dsaSignature = maybeDsa;
        if (maybeEd25519 != nil) {
            NSString *ed = maybeEd25519;
            NSData *data;
            if (@available(macOS 10.9, *)) {
                data = [[NSData alloc] initWithBase64EncodedString:ed options:0];
            } else {
                data = [[NSData alloc] initWithBase64Encoding:ed];
            }
            assert(64 == sizeof(self->ed25519_signature));
            [data getBytes:self->ed25519_signature length:sizeof(self->ed25519_signature)];
        }
    }
    return self;
}
@end
