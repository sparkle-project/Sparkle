//
//  SUCodeSigningVerifier.m
//  Sparkle
//
//  Created by Andy Matuschak on 7/5/12.
//
//

#import <Security/CodeSigning.h>
#import "SUCodeSigningVerifier.h"
#import "SULog.h"

@implementation SUCodeSigningVerifier

extern OSStatus SecCodeCopySelf(SecCSFlags flags, SecCodeRef *self)  __attribute__((weak_import));
extern OSStatus SecCodeCopyDesignatedRequirement(SecStaticCodeRef code, SecCSFlags flags, SecRequirementRef *requirement) __attribute__((weak_import));
extern OSStatus SecStaticCodeCreateWithPath(CFURLRef path, SecCSFlags flags, SecStaticCodeRef *staticCode) __attribute__((weak_import));
extern OSStatus SecStaticCodeCheckValidityWithErrors(SecStaticCodeRef staticCode, SecCSFlags flags, SecRequirementRef requirement, CFErrorRef *errors) __attribute__((weak_import));
extern OSStatus SecRequirementCreateWithString(CFStringRef text, SecCSFlags flags, SecRequirementRef *requirement) __attribute__((weak_import));
extern OSStatus SecCodeCheckValidity(SecCodeRef code, SecCSFlags flags, SecRequirementRef requirement) __attribute__((weak_import));

+ (BOOL)codeSignatureIsValidAtPath:(NSString *)destinationPath error:(NSError **)error
{
    // This API didn't exist prior to 10.6.
    if (SecCodeCopySelf == NULL) return NO;
    
    OSStatus result;
    SecRequirementRef requirement = NULL;
    SecStaticCodeRef staticCode = NULL;
    SecCodeRef hostCode = NULL;
    
    result = SecCodeCopySelf(kSecCSDefaultFlags, &hostCode);
    if (result != 0) {
        SULog(@"Failed to copy host code %d", result);
        goto finally;
    }
    
    result = SecCodeCopyDesignatedRequirement(hostCode, kSecCSDefaultFlags, &requirement);
    if (result != 0) {
        SULog(@"Failed to copy designated requirement %d", result);
        goto finally;
    }
    
    NSBundle *newBundle = [NSBundle bundleWithPath:destinationPath];
    if (!newBundle) {
        SULog(@"Failed to load NSBundle for update");
        result = -1;
        goto finally;
    }
    
    result = SecStaticCodeCreateWithPath((CFURLRef)[newBundle executableURL], kSecCSDefaultFlags, &staticCode);
    if (result != 0) {
        SULog(@"Failed to get static code %d", result);
        goto finally;
    }
    
    result = SecStaticCodeCheckValidityWithErrors(staticCode, kSecCSDefaultFlags | kSecCSCheckAllArchitectures, requirement, (CFErrorRef *)error);
    if (result != 0 && error) [*error autorelease];
    
finally:
    if (hostCode) CFRelease(hostCode);
    if (staticCode) CFRelease(staticCode);
    if (requirement) CFRelease(requirement);
    return (result == 0);
}

+ (BOOL)hostApplicationIsCodeSigned
{
    // This API didn't exist prior to 10.6.
    if (SecCodeCopySelf == NULL) return NO;
    
    OSStatus result;
    SecCodeRef hostCode = NULL;
    result = SecCodeCopySelf(kSecCSDefaultFlags, &hostCode);
    if (result != 0) return NO;
    
    SecRequirementRef requirement = NULL;
    result = SecCodeCopyDesignatedRequirement(hostCode, kSecCSDefaultFlags, &requirement);
    if (hostCode) CFRelease(hostCode);
    if (requirement) CFRelease(requirement);
    return (result == 0);
}

+ (BOOL)hostApplicationIsSandboxed
{
    // This API didn't exist prior to 10.6
    if (SecCodeCopySelf == NULL) return NO;
    
    BOOL isSandboxed = NO;
    do
    {
        SecCodeRef hostCode = NULL;
        SecRequirementRef hostRequirement = NULL;
        
        #define Cleanup() \
        { \
            if (hostCode) CFRelease(hostCode); \
            if (hostRequirement) CFRelease(hostRequirement); \
        }
        
        OSStatus status = SecCodeCopySelf(kSecCSDefaultFlags, &hostCode);
    
        if (status != noErr || hostCode == NULL)
        {
            Cleanup();
            break;
        }
    
        CFStringRef requirementString = CFSTR("entitlement[\"com.apple.security.app-sandbox\"] exists");
        status = SecRequirementCreateWithString(requirementString, kSecCSDefaultFlags, &hostRequirement);

        if (status != noErr || hostRequirement == NULL)
        {
            Cleanup();
            break;
        }
        
        status = SecCodeCheckValidity(hostCode, kSecCSDefaultFlags, hostRequirement);
        if (noErr == status)
            isSandboxed = YES;
        
        Cleanup();
    }
    while (NO);

    return isSandboxed;
}

@end
