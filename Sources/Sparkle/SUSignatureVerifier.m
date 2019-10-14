//
//  SUDSAVerifier.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/16/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//
//  Includes code by Zach Waldowski on 10/18/13.
//  Copyright 2014 Big Nerd Ranch. Licensed under MIT.
//
//  Includes code from Plop by Mark Hamlin.
//  Copyright 2011 Mark Hamlin. Licensed under BSD.
//

#import "SUSignatureVerifier.h"
#import "SULog.h"
#import "SUSignatures.h"
#include <CommonCrypto/CommonDigest.h>
#import "ed25519.h" // Run `git submodule update --init` if you get an error here


#include "AppKitPrevention.h"

@interface SUSignatureVerifier ()
@property (readonly) SUPublicKeys *pubKeys;
@end

@implementation SUSignatureVerifier {
}

@synthesize pubKeys = _pubKeys;

+ (BOOL)validatePath:(NSString *)path withSignatures:(SUSignatures *)signatures withPublicKeys:(SUPublicKeys *)pkeys
{
    SUSignatureVerifier *verifier = [(SUSignatureVerifier *)[self alloc] initWithPublicKeys:pkeys];

    if (!verifier) {
        return NO;
    }

    return [verifier verifyFileAtPath:path signatures:signatures];
}

- (instancetype)initWithPublicKeys:(SUPublicKeys *)pubkeys
{
    self = [super init];
    _pubKeys = pubkeys;

    return self;
}

- (SecKeyRef)dsaSecKeyRef {

    NSData *data = [self.pubKeys.dsaPubKey dataUsingEncoding:NSASCIIStringEncoding];
    if (!self || !data.length) {
        SULog(SULogLevelError, @"Could not read public DSA key");
        return nil;
    }

    SecExternalFormat format = kSecFormatOpenSSL;
    SecExternalItemType itemType = kSecItemTypePublicKey;
    CFArrayRef items = NULL;

    OSStatus status = SecItemImport((__bridge CFDataRef)data, NULL, &format, &itemType, (SecItemImportExportFlags)0, NULL, NULL, &items);
    if (status != errSecSuccess || !items) {
        if (items) {
            CFRelease(items);
        }
        SULog(SULogLevelError, @"Public DSA key could not be imported: %d", status);
        return nil;
    }

    SecKeyRef dsaPubKeySecKey = nil;
    if (format == kSecFormatOpenSSL && itemType == kSecItemTypePublicKey && CFArrayGetCount(items) == 1) {
        // Seems silly, but we can't quiet the warning about dropping CFTypeRef's const qualifier through
        // any manner of casting I've tried, including interim explicit cast to void*. The -Wcast-qual
        // warning is on by default with -Weverything and apparently became more noisy as of Xcode 7.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-qual"
        dsaPubKeySecKey = (SecKeyRef)CFRetain(CFArrayGetValueAtIndex(items, 0));
#pragma clang diagnostic pop
    }

    CFRelease(items);
    return dsaPubKeySecKey;
}

- (BOOL)verifyFileAtPath:(NSString *)path signatures:(SUSignatures *)signatures
{
    if (!path || !path.length) {
        return NO;
    }

    if (!signatures) {
        SULog(SULogLevelDefault, @"No signatures given to verifyFileAtPath");
        return NO;
    }

    NSData *dsaSignature = signatures.dsaSignature;
    NSString *dsaPubKey = self.pubKeys.dsaPubKey;

    const unsigned char *edSignature = signatures.ed25519Signature;
    const unsigned char *edPubKey = self.pubKeys.ed25519PubKey;

    if (edPubKey && !edSignature) {
        SULog(SULogLevelDefault, @"There is no EdDSA signature in the update, but the app is capable of verifying them");
    } if (!edPubKey && edSignature) {
        SULog(SULogLevelDefault, @"The update has an EdDSA signature, but it won't be used, because the old app doesn't have an EdDSA public key");
    } else if (edPubKey && edSignature) {
        NSError *error = nil;
        NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedAlways error:&error];
        if (!data || !data.length) {
            SULog(SULogLevelError, @"Failed to load file %@: %@", path, error);
            return NO;
        }
        if (ed25519_verify(edSignature, data.bytes, data.length, edPubKey)) {
            SULog(SULogLevelDefault, @"OK: EdDSA signature is correct");
            if (!dsaPubKey) {
                return YES;
            } else {
                SULog(SULogLevelDefault, @"This app has a DSA public key, so a DSA signature is required too");
            }
        } else {
            SULog(SULogLevelError, @"EdDSA signature does not match. Data of the update file being checked is different than data that has been signed, or the public key and the private key are not from the same set.");
            if (dsaSignature) {
                SULog(SULogLevelDefault, @"DSA signature won't be checked, because EdDSA verification has already failed");
            }
            return NO;
        }
    }

    if (!dsaSignature) {
        SULog(SULogLevelError, @"There is no DSA signature in the update");
    } else if (!dsaPubKey) {
        SULog(SULogLevelDefault, @"The update has a DSA signature, but it can't be used, because the old app doesn't have a DSA public key");
    } else {
        NSInputStream *dataInputStream = [NSInputStream inputStreamWithFileAtPath:path];
        return [self verifyDSASignatureOfStream:dataInputStream dsaSignature:dsaSignature];
    }
    return NO;
}

- (BOOL)verifyDSASignatureOfStream:(NSInputStream *)stream dsaSignature:(NSData *)dsaSignature
{
    if (!stream || !dsaSignature) {
        SULog(SULogLevelError, @"Invalid arguments to verifyStream");
        return NO;
    }

    SecKeyRef dsaPubKeySecKey = [self dsaSecKeyRef];
    if (!dsaPubKeySecKey) {
        return NO;
    }

    __block SecGroupTransformRef group = SecTransformCreateGroupTransform();
    __block SecTransformRef dataReadTransform = NULL;
    __block SecTransformRef dataDigestTransform = NULL;
    __block SecTransformRef dataVerifyTransform = NULL;
    __block CFErrorRef error = NULL;

    BOOL (^cleanup)(void) = ^{
		if (group) CFRelease(group);
		if (dataReadTransform) CFRelease(dataReadTransform);
		if (dataDigestTransform) CFRelease(dataDigestTransform);
		if (dataVerifyTransform) CFRelease(dataVerifyTransform);
		if (error) CFRelease(error);
        if (dsaPubKeySecKey) CFRelease(dsaPubKeySecKey);
		return NO;
    };

    dataReadTransform = SecTransformCreateReadTransformWithReadStream((__bridge CFReadStreamRef)stream);
    if (!dataReadTransform) {
        SULog(SULogLevelError, @"File containing update archive could not be read (failed to create SecTransform for input stream)");
        return cleanup();
    }

    dataDigestTransform = SecDigestTransformCreate(kSecDigestSHA1, CC_SHA1_DIGEST_LENGTH, NULL);
    if (!dataDigestTransform) {
        return cleanup();
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdirect-ivar-access"
    dataVerifyTransform = SecVerifyTransformCreate(dsaPubKeySecKey, (__bridge CFDataRef)dsaSignature, &error);
#pragma clang diagnostic pop
    if (!dataVerifyTransform || error) {
        SULog(SULogLevelError, @"Could not understand format of the signature: %@; Signature data: %@", error, dsaSignature);
        return cleanup();
    }

    SecTransformConnectTransforms(dataReadTransform, kSecTransformOutputAttributeName, dataDigestTransform, kSecTransformInputAttributeName, group, &error);
    if (error) {
        SULog(SULogLevelError, @"%@", error);
        return cleanup();
    }

    SecTransformConnectTransforms(dataDigestTransform, kSecTransformOutputAttributeName, dataVerifyTransform, kSecTransformInputAttributeName, group, &error);
    if (error) {
        SULog(SULogLevelError, @"%@", error);
        return cleanup();
    }

    NSNumber *result = CFBridgingRelease(SecTransformExecute(group, &error));
    if (error) {
        SULog(SULogLevelError, @"DSA signature verification failed: %@", error);
        return cleanup();
    }

    if (!result.boolValue) {
        SULog(SULogLevelError, @"DSA signature does not match. Data of the update file being checked is different than data that has been signed, or the public key and the private key are not from the same set.");
    }

    cleanup();
    return result.boolValue;
}

@end
