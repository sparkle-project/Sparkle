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
    static BOOL sIsCodesigned = NO;
    
    static BOOL onceToken = NO;
    while (!onceToken)
    {
        onceToken = YES;
        
        // This API didn't exist prior to 10.6.
        if (SecCodeCopySelf == NULL)
            break;
    
        SecCodeRef hostCode = NULL;
        OSStatus result = SecCodeCopySelf(kSecCSDefaultFlags, &hostCode);
        if (result != noErr)
            break;
    
        SecRequirementRef requirement = NULL;
        result = SecCodeCopyDesignatedRequirement(hostCode, kSecCSDefaultFlags, &requirement);
        
        if (hostCode) CFRelease(hostCode);
        if (requirement) CFRelease(requirement);
        
        sIsCodesigned = (noErr == result);
    }
    
    return sIsCodesigned;
}

+ (BOOL)hostApplicationIsSandboxed
{
    static BOOL sIsAppSandboxed = NO;
    
    static BOOL onceToken = NO;
    while (!onceToken)
    {
        onceToken = YES;
        
        // This API didn't exist prior to 10.6
        if (SecCodeCopySelf == NULL)
            break;
    
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
        sIsAppSandboxed = (noErr == status);
        Cleanup();
    }

    return sIsAppSandboxed;
}

+ (BOOL)hostAppAllowsNetworkOutgoingConnections
{
    static BOOL sIsAppAllowsOutgoingConnections = NO;
    
    static BOOL onceToken = NO;
    while (!onceToken)
    {
        onceToken = YES;
        
        if (![self hostApplicationIsSandboxed])
        {
            sIsAppAllowsOutgoingConnections = YES;
            break;
        }
        
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
        
        CFStringRef requirementString = CFSTR("entitlement[\"com.apple.security.network.client\"] exists");
        status = SecRequirementCreateWithString(requirementString, kSecCSDefaultFlags, &hostRequirement);
        if (status != noErr || hostRequirement == NULL)
        {
            Cleanup();
            break;
        }
        
        status = SecCodeCheckValidity(hostCode, kSecCSDefaultFlags, hostRequirement);
        sIsAppAllowsOutgoingConnections = (noErr == status);
        Cleanup();
    }
    
    return sIsAppAllowsOutgoingConnections;
}

@end

#pragma mark -

BOOL SUShouldUseXPCDownloader(void)
{
    if ([SUCodeSigningVerifier hostAppAllowsNetworkOutgoingConnections])
        return NO;
    
    NSString *xpcServicePrefixPath = [[NSBundle mainBundle] bundlePath];
    NSString *xpcServiceSuffixPath = @"Contents/XPCServices/com.devmate.UpdateDownloader.xpc";
	return [[NSFileManager defaultManager] fileExistsAtPath:[xpcServicePrefixPath stringByAppendingPathComponent:xpcServiceSuffixPath]];
}

BOOL SUShouldUseXPCInstaller(void)
{
    if (![SUCodeSigningVerifier hostApplicationIsSandboxed])
        return NO;
    
    NSString *xpcServicePrefixPath = [[NSBundle mainBundle] bundlePath];
    NSString *xpcServiceSuffixPath = @"Contents/XPCServices/com.devmate.UpdateInstaller.xpc";
	return [[NSFileManager defaultManager] fileExistsAtPath:[xpcServicePrefixPath stringByAppendingPathComponent:xpcServiceSuffixPath]];
}

