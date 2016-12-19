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

@implementation SUCodeSigningVerifier

+ (BOOL)codeSignatureAtBundleURL:(NSURL *)oldBundleURL matchesSignatureAtBundleURL:(NSURL *)newBundleURL error:(NSError *__autoreleasing *)error
{
    OSStatus result;
    SecRequirementRef requirement = NULL;
    SecStaticCodeRef staticCode = NULL;
    SecStaticCodeRef oldCode = NULL;
    CFErrorRef cfError = NULL;
    if (error) {
        *error = nil;
    }

    result = SecStaticCodeCreateWithPath((__bridge CFURLRef)oldBundleURL, kSecCSDefaultFlags, &oldCode);
    if (result == errSecCSUnsigned) {
        return NO;
    }

    result = SecCodeCopyDesignatedRequirement(oldCode, kSecCSDefaultFlags, &requirement);
    if (result != noErr) {
        SULog(@"Failed to copy designated requirement. Code Signing OSStatus code: %d", result);
        goto finally;
    }

    result = SecStaticCodeCreateWithPath((__bridge CFURLRef)newBundleURL, kSecCSDefaultFlags, &staticCode);
    if (result != noErr) {
        SULog(@"Failed to get static code %d", result);
        goto finally;
    }
    
    // Note that kSecCSCheckNestedCode may not work with pre-Mavericks code signing.
    // See https://github.com/sparkle-project/Sparkle/issues/376#issuecomment-48824267 and https://developer.apple.com/library/mac/technotes/tn2206
    // Aditionally, there are several reasons to stay away from deep verification and to prefer DSA signing the download archive instead.
    // See https://github.com/sparkle-project/Sparkle/pull/523#commitcomment-17549302 and https://github.com/sparkle-project/Sparkle/issues/543
    SecCSFlags flags = (SecCSFlags) (kSecCSDefaultFlags | kSecCSCheckAllArchitectures);
    result = SecStaticCodeCheckValidityWithErrors(staticCode, flags, requirement, &cfError);
    
    if (cfError) {
        NSError *tmpError = CFBridgingRelease(cfError);
        if (error) *error = tmpError;
    }
    
    if (result != noErr) {
        if (result == errSecCSUnsigned) {
            SULog(@"The host app is signed, but the new version of the app is not signed using Apple Code Signing. Please ensure that the new app is signed and that archiving did not corrupt the signature.");
        }
        if (result == errSecCSReqFailed) {
            CFStringRef requirementString = nil;
            if (SecRequirementCopyString(requirement, kSecCSDefaultFlags, &requirementString) == noErr) {
                SULog(@"Code signature of the new version doesn't match the old version: %@. Please ensure that old and new app is signed using exactly the same certificate.", requirementString);
                CFRelease(requirementString);
            }
            
            [self logSigningInfoForCode:oldCode label:@"old info"];
            [self logSigningInfoForCode:staticCode label:@"new info"];
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
    OSStatus result;
    SecStaticCodeRef staticCode = NULL;
    CFErrorRef cfError = NULL;
    if (error) {
        *error = nil;
    }

    result = SecStaticCodeCreateWithPath((__bridge CFURLRef)bundleURL, kSecCSDefaultFlags, &staticCode);
    if (result != noErr) {
        SULog(@"Failed to get static code %d", result);
        goto finally;
    }

    // See in -codeSignatureAtBundleURL:matchesSignatureAtBundleURL:error: for why kSecCSCheckNestedCode is not passed
    SecCSFlags flags = (SecCSFlags) (kSecCSDefaultFlags | kSecCSCheckAllArchitectures);
    result = SecStaticCodeCheckValidityWithErrors(staticCode, flags, NULL, &cfError);
    
    if (cfError) {
        NSError *tmpError = CFBridgingRelease(cfError);
        if (error) *error = tmpError;
    }
    
    if (result != noErr) {
        if (result == errSecCSUnsigned) {
            SULog(@"Error: The app is not signed using Apple Code Signing. %@", bundleURL);
        }
        if (result == errSecCSReqFailed) {
            [self logSigningInfoForCode:staticCode label:@"new info"];
        }
    }
    
finally:
    if (staticCode) CFRelease(staticCode);
    return (result == noErr);
}

static id valueOrNSNull(id value) {
    return value ? value : [NSNull null];
}

+ (void)logSigningInfoForCode:(SecStaticCodeRef)code label:(NSString*)label {
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
        SULog(@"%@: %@", label, relevantInfo);
    }
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

@end
