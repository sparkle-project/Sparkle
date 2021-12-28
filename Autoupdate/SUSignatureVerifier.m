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
#import "SUErrors.h"
#include <CommonCrypto/CommonDigest.h>
#import "ed25519.h" // Run `git submodule update --init` if you get an error here


#include "AppKitPrevention.h"

@interface SUSignatureVerifier ()
@property (readonly) SUPublicKeys *pubKeys;
@end

@implementation SUSignatureVerifier {
}

@synthesize pubKeys = _pubKeys;

+ (BOOL)validatePath:(NSString *)path withSignatures:(SUSignatures *)signatures withPublicKeys:(SUPublicKeys *)pkeys error:(NSError * __autoreleasing *)error
{
    SUSignatureVerifier *verifier = [(SUSignatureVerifier *)[self alloc] initWithPublicKeys:pkeys];

    if (verifier == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: @"Failed to create SUSignatureVerifier instance" }];
        }
        return NO;
    }

    return [verifier verifyFileAtPath:path signatures:signatures error:error];
}

- (instancetype)initWithPublicKeys:(SUPublicKeys *)pubkeys
{
    self = [super init];
    if (self != nil) {
        _pubKeys = pubkeys;
    }
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

- (BOOL)verifyFileAtPath:(NSString *)path signatures:(SUSignatures *)signatures error:(NSError * __autoreleasing *)error
{
    if (!path || !path.length) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: @"Path passed to verify has zero length and is not valid" }];
        }
        return NO;
    }

    if (!signatures) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: @"No signatures given to verifyFileAtPath" }];
        }
        return NO;
    }

    switch (self.pubKeys.ed25519PubKeyStatus) {
    case SUSigningInputStatusAbsent:
        if (signatures.ed25519SignatureStatus != SUSigningInputStatusAbsent) {
            SULog(SULogLevelDefault, @"The update has an EdDSA signature, but it won't be used, because the old app doesn't have an EdDSA public key");
        }
        break;
    case SUSigningInputStatusInvalid:
        if (signatures.ed25519SignatureStatus != SUSigningInputStatusAbsent) {
            NSString *message = @"The update has an EdDSA signature, but the app has an invalid EdDSA public key, so the update will automatically be rejected.";
            SULog(SULogLevelError, @"%@", message);
            
            if (error != NULL) {
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: message }];
            }
            
            return NO;
        }
        SULog(SULogLevelDefault, @"The app has an invalid EdDSA public key, but there is no EdDSA signature in the update. Falling back to DSA.");
        break;
    case SUSigningInputStatusPresent:
        switch (signatures.ed25519SignatureStatus) {
        case SUSigningInputStatusAbsent: {
            NSString *message = @"The app has an EdDSA public key, but there is no EdDSA signature in the update, so the update will be rejected.";
            SULog(SULogLevelError, @"%@", message);
                
            if (error != NULL) {
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: message }];
            }
            
            return NO;
        }
        case SUSigningInputStatusInvalid: {
            NSString *message = @"The update has an EdDSA signature, but it's invalid, so the update will automatically be rejected.";
            
            SULog(SULogLevelError, @"%@", message);
                
            if (error != NULL) {
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: message }];
            }
            return NO;
        }
        case SUSigningInputStatusPresent: {
            NSError *dataError = nil;
            NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedAlways error:&dataError];
            if (!data || !data.length) {
                SULog(SULogLevelError, @"Failed to load file %@: %@", path, dataError);
                
                if (error != NULL) {
                    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
                    userInfo[NSLocalizedDescriptionKey] = [NSString stringWithFormat:@"Failed to load file: %@", path];
                    if (dataError != nil) {
                        userInfo[NSUnderlyingErrorKey] = dataError;
                    }
                    
                    *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:[userInfo copy]];
                }
                
                return NO;
            }
            if (ed25519_verify(signatures.ed25519Signature, data.bytes, data.length, self.pubKeys.ed25519PubKey)) {
                SULog(SULogLevelDefault, @"OK: EdDSA signature is correct");
                // No need to check DSA when EdDSA verification succeeded, unless a DSA signature is provided and it's
                // erroneously invalid
                if (signatures.dsaSignatureStatus != SUSigningInputStatusInvalid) {
                    return YES;
                }
            } else {
                NSString *message = @"EdDSA signature does not match. Data of the update file being checked is different than data that has been signed, or the public key and the private key are not from the same set.";
                
                SULog(SULogLevelError, @"%@", message);
                
                if (signatures.dsaSignatureStatus != SUSigningInputStatusAbsent) {
                    SULog(SULogLevelDefault, @"DSA signature won't be checked, because EdDSA verification has already failed");
                }
                
                if (error != NULL) {
                    *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: message }];
                }
                
                return NO;
            }
        }
        }
        break;
    }

    switch (self.pubKeys.dsaPubKeyStatus) {
    case SUSigningInputStatusAbsent:
        if (signatures.dsaSignatureStatus != SUSigningInputStatusAbsent) {
            SULog(SULogLevelDefault, @"The update has a DSA signature, but it can't be used, because the old app doesn't have a DSA public key");
        }
        break;
    case SUSigningInputStatusInvalid:
        if (signatures.dsaSignatureStatus != SUSigningInputStatusAbsent) {
            // We will have already logged an error for this failure when the public key was read in, so just do an informational log here.
            NSString *message = @"The update has a DSA signature, but the app has an invalid DSA public key, so the update will automatically be rejected.";
            
            SULog(SULogLevelError, @"%@", message);
            
            if (error != NULL) {
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: message }];
            }
            
            return NO;
        }
        SULog(SULogLevelDefault, @"The app has an invalid DSA public key, but there is no DSA signature in the update.");
        break;
    case SUSigningInputStatusPresent:
        switch (signatures.dsaSignatureStatus) {
        case SUSigningInputStatusAbsent:
            SULog(SULogLevelError, @"There is no DSA signature in the update");
            break;
        case SUSigningInputStatusInvalid: {
            NSString *message = @"The update has a DSA signature, but it's invalid, so the update will automatically be rejected.";
            
            SULog(SULogLevelError, @"%@", message);
                
            if (error != NULL) {
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: message }];
            }
            
            return NO;
        }
        case SUSigningInputStatusPresent: {
            NSInputStream *dataInputStream = [NSInputStream inputStreamWithFileAtPath:path];
            return [self verifyDSASignatureOfStream:dataInputStream dsaSignature:signatures.dsaSignature error:error];
        }
        }
    }

    if (error != NULL) {
        // Use generic failure
        *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: @"EdDSA and DSA verification for the update has failed" }];
    }
    
    return NO;
}

- (BOOL)verifyDSASignatureOfStream:(NSInputStream *)stream dsaSignature:(NSData *)dsaSignature error:(NSError * __autoreleasing *)outError
{
    if (!stream || !dsaSignature) {
        SULog(SULogLevelError, @"Invalid arguments to verifyStream");
        
        if (outError != NULL) {
            *outError = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: @"Invalid arguments to verifyStream" }];
        }
        
        return NO;
    }

    SecKeyRef dsaPubKeySecKey = [self dsaSecKeyRef];
    if (!dsaPubKeySecKey) {
        if (outError != NULL) {
            *outError = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: @"Failed to create DSA Sec Key Ref" }];
        }
        
        return NO;
    }

    // Sparkle's DSA support is deprecated
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    __block SecGroupTransformRef group = SecTransformCreateGroupTransform();
#pragma clang diagnostic pop
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
        if (outError != NULL) {
            *outError = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: @"File containing update archive could not be read (failed to create SecTransform for input stream)" }];
        }
        return cleanup();
    }

    dataDigestTransform = SecDigestTransformCreate(kSecDigestSHA1, CC_SHA1_DIGEST_LENGTH, NULL);
    if (!dataDigestTransform) {
        if (outError != NULL) {
            *outError = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: @"File containing update archive could not be read (failed to create SecDigest for input stream)" }];
        }
        
        return cleanup();
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdirect-ivar-access"
    dataVerifyTransform = SecVerifyTransformCreate(dsaPubKeySecKey, (__bridge CFDataRef)dsaSignature, &error);
#pragma clang diagnostic pop
    if (!dataVerifyTransform) {
        SULog(SULogLevelError, @"Could not understand format of the signature: %@; Signature data: %@", error, dsaSignature);
        if (outError != NULL) {
            NSError *underlyingError = (__bridge NSError *)error;
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
            userInfo[NSLocalizedDescriptionKey] = [NSString stringWithFormat:@"Could not understand format of the signature data %@", dsaSignature];
            if (underlyingError != NULL) {
                userInfo[NSUnderlyingErrorKey] = underlyingError;
            }
            
            *outError = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:[userInfo copy]];
        }
        
        return cleanup();
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    SecTransformConnectTransforms(dataReadTransform, kSecTransformOutputAttributeName, dataDigestTransform, kSecTransformInputAttributeName, group, &error);
#pragma clang diagnostic pop
    if (error) {
        if (outError != NULL) {
            *outError = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{NSLocalizedDescriptionKey : @"Failed to connect data read transform", NSUnderlyingErrorKey: (__bridge NSError *)error}];
        }
        
        return cleanup();
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    SecTransformConnectTransforms(dataDigestTransform, kSecTransformOutputAttributeName, dataVerifyTransform, kSecTransformInputAttributeName, group, &error);
#pragma clang diagnostic pop
    if (error) {
        if (outError != NULL) {
            *outError = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{NSLocalizedDescriptionKey : @"Failed to connect data digest transform", NSUnderlyingErrorKey: (__bridge NSError *)error}];
        }
        
        return cleanup();
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSNumber *result = CFBridgingRelease(SecTransformExecute(group, &error));
#pragma clang diagnostic pop
    if (error) {
        SULog(SULogLevelError, @"DSA signature verification failed: %@", error);
        if (outError != NULL) {
            *outError = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: @"DSA signature verification failed", NSUnderlyingErrorKey: (__bridge NSError *)error}];
        }
        
        return cleanup();
    }

    if (!result.boolValue) {
        if (outError != NULL) {
            *outError = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: @"DSA signature does not match. Data of the update file being checked is different than data that has been signed, or the public key and the private key are not from the same set"}];
        }
    }

    cleanup();
    return result.boolValue;
}

@end
