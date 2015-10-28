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

+ (BOOL)codeSignatureAtPath:(NSString *)hostPath matchesSignatureAtPath:(NSString *)otherAppPath error:(NSError *__autoreleasing *)error
{
    OSStatus result;
    SecRequirementRef requirement = NULL;
    SecStaticCodeRef staticHostCode = NULL;
    SecStaticCodeRef staticAppCode = NULL;

    if (error) {
        *error = nil;
    }

    if (0 == hostPath.length) {
        SecCodeRef hostCode = NULL;
        result = SecCodeCopySelf(kSecCSDefaultFlags, &hostCode);
        if (result != noErr) {
            SULog(@"Failed to copy host code %d", result);
            goto finally;
        }
        
        result = SecCodeCopyStaticCode(hostCode, kSecCSDefaultFlags, &staticHostCode);
        CFRelease(hostCode);
        if (result != noErr) {
            SULog(@"Failed to copy host code %d", result);
            goto finally;
        }
    } else {
        NSBundle *hostAppBundle = [NSBundle bundleWithPath:hostPath];
        if (nil == hostAppBundle) {
            SULog(@"Failed to create bundle at path %@", hostPath);
            result = -1;
            goto finally;
        }
        
        result = SecStaticCodeCreateWithPath((__bridge CFURLRef)hostAppBundle.bundleURL, kSecCSDefaultFlags, &staticHostCode);
        if (result != noErr) {
            SULog(@"Failed to copy host code %d", result);
            goto finally;
        }
    }
    
    result = SecCodeCopyDesignatedRequirement(staticHostCode, kSecCSDefaultFlags, &requirement);
    if (result != noErr) {
        SULog(@"Failed to copy designated requirement. Code Signing OSStatus code: %d", result);
        goto finally;
    }

    if (0 == otherAppPath.length) {
        SecCodeRef hostCode = NULL;
        result = SecCodeCopySelf(kSecCSDefaultFlags, &hostCode);
        if (result != noErr) {
            SULog(@"Failed to copy other app code %d", result);
            goto finally;
        }
        
        result = SecCodeCopyStaticCode(hostCode, kSecCSDefaultFlags, &staticAppCode);
        CFRelease(hostCode);
        if (result != noErr) {
            SULog(@"Failed to copy other app code %d", result);
            goto finally;
        }
    } else {
        NSBundle *otherAppBundle = [NSBundle bundleWithPath:otherAppPath];
        if (nil == otherAppBundle) {
            SULog(@"Failed to create bundle at path %@", otherAppPath);
            result = -1;
            goto finally;
        }
        
        result = SecStaticCodeCreateWithPath((__bridge CFURLRef)otherAppBundle.bundleURL, kSecCSDefaultFlags, &staticAppCode);
        if (result != noErr) {
            SULog(@"Failed to copy other app code %d", result);
            goto finally;
        }
    }

    // Note that kSecCSCheckNestedCode may not work with pre-Mavericks code signing.
    // See https://github.com/sparkle-project/Sparkle/issues/376#issuecomment-48824267 and https://developer.apple.com/library/mac/technotes/tn2206
    CFErrorRef cfError = NULL;
	SecCSFlags flags = (SecCSFlags) (kSecCSDefaultFlags | kSecCSCheckAllArchitectures);
    result = SecStaticCodeCheckValidityWithErrors(staticAppCode, flags, requirement, &cfError);

    if (cfError) {
        NSError *tmpError = CFBridgingRelease(cfError);
        if (error) {
            *error = tmpError;
        }
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

            [self logSigningInfoForCode:staticHostCode label:@"host info"];
            [self logSigningInfoForCode:staticAppCode label:@"new info"];
        }
    }

finally:
    if (staticHostCode) CFRelease(staticHostCode);
    if (staticAppCode) CFRelease(staticAppCode);
    if (requirement) CFRelease(requirement);
    return (result == noErr);
}

+ (BOOL)codeSignatureIsValidAtPath:(NSString *)applicationPath error:(NSError *__autoreleasing *)error
{
    OSStatus result;
    SecStaticCodeRef staticCode = NULL;
    NSBundle *newBundle;
    CFErrorRef cfError = NULL;
    if (error) {
        *error = nil;
    }

    newBundle = [NSBundle bundleWithPath:applicationPath];
    if (!newBundle) {
        SULog(@"Failed to load NSBundle");
        result = -1;
        goto finally;
    }

    result = SecStaticCodeCreateWithPath((__bridge CFURLRef)[newBundle bundleURL], kSecCSDefaultFlags, &staticCode);
    if (result != noErr) {
        SULog(@"Failed to get static code %d", result);
        goto finally;
    }

    // Note that kSecCSCheckNestedCode may not work with pre-Mavericks code signing.
    // See https://github.com/sparkle-project/Sparkle/issues/376#issuecomment-48824267 and https://developer.apple.com/library/mac/technotes/tn2206
	SecCSFlags flags = (SecCSFlags) (kSecCSDefaultFlags | kSecCSCheckAllArchitectures);
    result = SecStaticCodeCheckValidityWithErrors(staticCode, flags, NULL, &cfError);

    if (cfError) {
        NSError *tmpError = CFBridgingRelease(cfError);
        if (error) *error = tmpError;
    }

    if (result != noErr) {
        if (result == errSecCSUnsigned) {
            SULog(@"Error: The app is not signed using Apple Code Signing. %@", applicationPath);
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
            relevantInfo[key] = valueOrNSNull(signingDict[key]);
        }
        NSDictionary *infoPlist = signingDict[@"info-plist"];
        relevantInfo[@"version"] = valueOrNSNull(infoPlist[@"CFBundleShortVersionString"]);
        relevantInfo[@"build"] = valueOrNSNull(infoPlist[(__bridge NSString *)kCFBundleVersionKey]);
        SULog(@"%@: %@", label, relevantInfo);
    }
}

+ (BOOL)hostApplicationIsSandboxed
{
    static BOOL sIsAppSandboxed = NO;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        __block SecCodeRef hostCode = NULL;
        __block SecRequirementRef hostRequirement = NULL;
        
        void (^Cleanup)(void) = ^ {
            if (hostCode) { CFRelease(hostCode); hostCode = NULL; }
            if (hostRequirement) { CFRelease(hostRequirement); hostRequirement = NULL; }
        };
        
        OSStatus status = SecCodeCopySelf(kSecCSDefaultFlags, &hostCode);
        if (status != noErr || hostCode == NULL)
        {
            Cleanup();
            return;
        }
        
        CFStringRef requirementString = CFSTR("entitlement[\"com.apple.security.app-sandbox\"] exists");
        status = SecRequirementCreateWithString(requirementString, kSecCSDefaultFlags, &hostRequirement);
        
        if (status != noErr || hostRequirement == NULL)
        {
            Cleanup();
            return;
        }
        
        status = SecCodeCheckValidity(hostCode, kSecCSDefaultFlags, hostRequirement);
        sIsAppSandboxed = (noErr == status);
        Cleanup();
    });
    
    return sIsAppSandboxed;
}

+ (BOOL)applicationAtPathIsCodeSigned:(NSString *)applicationPath
{
    OSStatus result;
    SecStaticCodeRef staticCode = NULL;
    NSBundle *newBundle;

    newBundle = [NSBundle bundleWithPath:applicationPath];
    if (!newBundle) {
        SULog(@"Failed to load NSBundle");
    	return NO;
    }

    result = SecStaticCodeCreateWithPath((__bridge CFURLRef)[newBundle bundleURL], kSecCSDefaultFlags, &staticCode);
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
