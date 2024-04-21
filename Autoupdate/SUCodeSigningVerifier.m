//
//  SUCodeSigningVerifier.m
//  Sparkle
//
//  Created by Andy Matuschak on 7/5/12.
//
//

#include <Security/CodeSigning.h>
#include <Security/SecCode.h>
#import "SUCodeSigningVerifier.h"
#import "SULog.h"
#import "SUErrors.h"


#include "AppKitPrevention.h"

@implementation SUCodeSigningVerifier

+ (BOOL)codeSignatureIsValidAtBundleURL:(NSURL *)newBundleURL andMatchesSignatureAtBundleURL:(NSURL *)oldBundleURL error:(NSError * __autoreleasing *)error
{
    OSStatus result;
    SecRequirementRef requirement = NULL;
    SecStaticCodeRef staticCode = NULL;
    SecStaticCodeRef oldCode = NULL;
    CFErrorRef cfError = NULL;

    result = SecStaticCodeCreateWithPath((__bridge CFURLRef)oldBundleURL, kSecCSDefaultFlags, &oldCode);
    if (result == errSecCSUnsigned) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInsufficientSigningError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Bundle is not code signed: %@", newBundleURL] }];
        }
        
        return NO;
    }

    result = SecCodeCopyDesignatedRequirement(oldCode, kSecCSDefaultFlags, &requirement);
    if (result != noErr) {
        NSString *message = [NSString stringWithFormat:@"Failed to copy designated requirement. Code Signing OSStatus code: %d", result];
        SULog(SULogLevelError, @"%@", message);
        
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInsufficientSigningError userInfo:@{ NSLocalizedDescriptionKey: message }];
        }
        
        goto finally;
    }

    result = SecStaticCodeCreateWithPath((__bridge CFURLRef)newBundleURL, kSecCSDefaultFlags, &staticCode);
    if (result != noErr) {
        NSString *message = [NSString stringWithFormat:@"Failed to get static code %d", result];
        
        SULog(SULogLevelError, @"%@", message);
        
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInsufficientSigningError userInfo:@{ NSLocalizedDescriptionKey: message }];
        }
        
        goto finally;
    }
    
    // Note that kSecCSCheckNestedCode may not work with pre-Mavericks code signing.
    // See https://github.com/sparkle-project/Sparkle/issues/376#issuecomment-48824267 and https://developer.apple.com/library/mac/technotes/tn2206
    // Additionally, there are several reasons to stay away from deep verification and to prefer EdDSA signing the download archive instead.
    // See https://github.com/sparkle-project/Sparkle/pull/523#commitcomment-17549302 and https://github.com/sparkle-project/Sparkle/issues/543
    SecCSFlags flags = (SecCSFlags) (kSecCSDefaultFlags | kSecCSCheckAllArchitectures);
    result = SecStaticCodeCheckValidityWithErrors(staticCode, flags, requirement, &cfError);
    
    if (result != errSecSuccess) {
        NSError *underlyingError;
        if (cfError != NULL) {
            NSError *tmpError = CFBridgingRelease(cfError);
            underlyingError = tmpError;
        } else {
            underlyingError = nil;
        }
        
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
        if (underlyingError != nil) {
            userInfo[NSUnderlyingErrorKey] = underlyingError;
        }
        
        if (result == errSecCSUnsigned) {
            NSString *message = @"The host app is signed, but the new version of the app is not signed using Apple Code Signing. Please ensure that the new app is signed and that archiving did not corrupt the signature.";
            
            SULog(SULogLevelError, @"%@", message);
            
            if (error != NULL) {
                userInfo[NSLocalizedDescriptionKey] = message;
                
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInsufficientSigningError userInfo:[userInfo copy]];
            }
        } else if (result == errSecCSReqFailed) {
            CFStringRef requirementString = nil;
            NSString *initialMessage;
            if (SecRequirementCopyString(requirement, kSecCSDefaultFlags, &requirementString) == noErr) {
                initialMessage = [NSString stringWithFormat:@"Code signature of the new version doesn't match the old version: %@. Please ensure that old and new app is signed using exactly the same certificate.", requirementString];
                
                SULog(SULogLevelError, @"%@", initialMessage);
                CFRelease(requirementString);
            } else {
                initialMessage = @"Code signature of new version doesn't match the old version. Please ensure that old and new app is signed using exactly the same certificate.";
            }
            
            NSDictionary *oldInfo = [self logSigningInfoForCode:oldCode label:@"old info"];
            NSDictionary *newInfo = [self logSigningInfoForCode:staticCode label:@"new info"];
            
            if (error != NULL) {
                userInfo[NSLocalizedDescriptionKey] = [NSString stringWithFormat:@"%@ old info: %@. new info: %@", initialMessage, oldInfo, newInfo];
                
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInsufficientSigningError userInfo:[userInfo copy]];
            }
        } else {
            if (error != NULL) {
                userInfo[NSLocalizedDescriptionKey] = @"Error: Old app bundle code signing signature failed to match new bundle code signature";
                
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInsufficientSigningError userInfo:[userInfo copy]];
            }
        }
    }
    
finally:
    if (oldCode) CFRelease(oldCode);
    if (staticCode) CFRelease(staticCode);
    if (requirement) CFRelease(requirement);
    return (result == noErr);
}

+ (BOOL)codeSignatureIsValidAtBundleURL:(NSURL *)bundleURL error:(NSError *__autoreleasing *)error
{
    return [self codeSignatureIsValidAtBundleURL:bundleURL checkNestedCode:NO error:error];
}

+ (BOOL)codeSignatureIsValidAtBundleURL:(NSURL *)bundleURL checkNestedCode:(BOOL)checkNestedCode error:(NSError *__autoreleasing *)error
{
    OSStatus result;
    SecStaticCodeRef staticCode = NULL;
    CFErrorRef cfError = NULL;
    
    result = SecStaticCodeCreateWithPath((__bridge CFURLRef)bundleURL, kSecCSDefaultFlags, &staticCode);
    if (result != noErr) {
        SULog(SULogLevelError, @"Failed to get static code %d", result);
        
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInsufficientSigningError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to get static code for verifying code signature: %d", result] }];
        }
        
        goto finally;
    }

    // See in -codeSignatureIsValidAtBundleURL:andMatchesSignatureAtBundleURL:error: for why kSecCSCheckNestedCode is not always passed
    SecCSFlags flags = (SecCSFlags) (kSecCSDefaultFlags | kSecCSCheckAllArchitectures);
    if (checkNestedCode) {
        flags |= kSecCSCheckNestedCode;
    }
    
    result = SecStaticCodeCheckValidityWithErrors(staticCode, flags, NULL, &cfError);
    
    if (result != errSecSuccess) {
        NSError *underlyingError;
        if (cfError != NULL) {
            NSError *tmpError = CFBridgingRelease(cfError);
            underlyingError = tmpError;
        } else {
            underlyingError = nil;
        }
        
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
        if (underlyingError != nil) {
            userInfo[NSUnderlyingErrorKey] = underlyingError;
        }
        
        if (result == errSecCSUnsigned) {
            NSString *message = [NSString stringWithFormat:@"Error: The app is not signed using Apple Code Signing. %@", bundleURL];
            SULog(SULogLevelError, @"%@", message);
            
            if (error != NULL) {
                userInfo[NSLocalizedDescriptionKey] = message;
                
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInsufficientSigningError userInfo:[userInfo copy]];
            }
        } else if (result == errSecCSReqFailed) {
            if (error != NULL) {
                NSDictionary *newInfo = [self logSigningInfoForCode:staticCode label:@"new info"];
                
                NSString *message = [NSString stringWithFormat:@"Error: The app failed Apple Code Signing checks: %@ - new info: %@", bundleURL, newInfo];
                
                userInfo[NSLocalizedDescriptionKey] = message;
                
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInsufficientSigningError userInfo:[userInfo copy]];
            }
        } else {
            if (error != NULL) {
                NSString *message = [NSString stringWithFormat:@"Error: The app failed Apple Code Signing checks: %@", bundleURL];
                
                userInfo[NSLocalizedDescriptionKey] = message;
                
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInsufficientSigningError userInfo:[userInfo copy]];
            }
        }
    }
    
finally:
    if (staticCode) CFRelease(staticCode);
    return (result == noErr);
}

static id valueOrNSNull(id value) {
    return value ? value : [NSNull null];
}

+ (NSDictionary *)codeSignatureInfoForCode:(SecStaticCodeRef)code SPU_OBJC_DIRECT
{
    CFDictionaryRef signingInfo = nil;
    const SecCSFlags flags = (SecCSFlags) (kSecCSSigningInformation | kSecCSRequirementInformation | kSecCSDynamicInformation | kSecCSContentInformation);
    if (SecCodeCopySigningInformation(code, flags, &signingInfo) == noErr) {
        NSDictionary *signingDict = CFBridgingRelease(signingInfo);
        NSMutableDictionary *relevantInfo = [NSMutableDictionary dictionary];
        for (NSString *key in @[@"format", @"identifier", @"requirements", @"teamid", @"signing-time"]) {
            [relevantInfo setObject:valueOrNSNull([signingDict objectForKey:key]) forKey:key];
        }
        NSDictionary *infoPlist = [signingDict objectForKey:@"info-plist"];
        [relevantInfo setObject:valueOrNSNull([infoPlist objectForKey:@"CFBundleShortVersionString"]) forKey:@"version"];
        [relevantInfo setObject:valueOrNSNull([infoPlist objectForKey:(__bridge NSString *)kCFBundleVersionKey]) forKey:@"build"];
        return [relevantInfo copy];
    }
    return nil;
}

+ (NSDictionary *)logSigningInfoForCode:(SecStaticCodeRef)code label:(NSString*)label SPU_OBJC_DIRECT
{
    NSDictionary *relevantInfo = [self codeSignatureInfoForCode:code];
    SULog(SULogLevelDefault, @"%@: %@", label, relevantInfo);
    return relevantInfo;
}

+ (BOOL)bundleAtURLIsCodeSigned:(NSURL *)bundleURL
{
    OSStatus result;
    SecStaticCodeRef staticCode = NULL;

    result = SecStaticCodeCreateWithPath((__bridge CFURLRef)bundleURL, kSecCSDefaultFlags, &staticCode);
    if (result == errSecCSUnsigned) {
        return NO;
    }

    SecRequirementRef requirement = NULL;
    result = SecCodeCopyDesignatedRequirement(staticCode, kSecCSDefaultFlags, &requirement);
    if (staticCode) {
        CFRelease(staticCode);
    }
    if (requirement) {
        CFRelease(requirement);
    }
    if (result == errSecCSUnsigned) {
        return NO;
    }
    return (result == 0);
}

+ (NSString * _Nullable)teamIdentifierAtURL:(NSURL *)url
{
    SecStaticCodeRef staticCode = NULL;
    OSStatus staticCodeResult = SecStaticCodeCreateWithPath((__bridge CFURLRef)url, kSecCSDefaultFlags, &staticCode);
    if (staticCodeResult != noErr) {
        SULog(SULogLevelError, @"Failed to get static code for retrieving team identifier: %d", staticCodeResult);
        return nil;
    }
    
    CFDictionaryRef cfSigningInformation = NULL;
    OSStatus copySigningInfoCode = SecCodeCopySigningInformation(staticCode, kSecCSSigningInformation,
        &cfSigningInformation);
    
    NSDictionary *signingInformation = CFBridgingRelease(cfSigningInformation);
    
    if (copySigningInfoCode != noErr) {
        SULog(SULogLevelError, @"Failed to get signing information for retrieving team identifier: %d", copySigningInfoCode);
        return nil;
    }
    
    // Note this will return nil for ad-hoc or unsigned binaries
    return signingInformation[(NSString *)kSecCodeInfoTeamIdentifier];
}

@end
