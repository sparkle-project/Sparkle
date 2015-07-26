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

+ (BOOL)codeSignatureIsValidAtPath:(NSString *)destinationPath error:(NSError **)error
{
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
    if (result != 0 && error) {
        if (result == errSecCSReqFailed) {
            CFStringRef requirementString = nil;
            if (SecRequirementCopyString(requirement, kSecCSDefaultFlags, &requirementString) == noErr) {
                SULog(@"Failed requirement %@", requirementString);
                CFRelease(requirementString);
            }

            [self logSigningInfoForCode:hostCode label:@"host info"];
            [self logSigningInfoForCode:staticCode label:@"new info"];
        }

        [*error autorelease];
    }

finally:
    if (hostCode) CFRelease(hostCode);
    if (staticCode) CFRelease(staticCode);
    if (requirement) CFRelease(requirement);
    return (result == 0);
}

+ (void)logSigningInfoForCode:(SecStaticCodeRef)code label:(NSString*)label {
    CFDictionaryRef signingInfo = nil;
    const SecCSFlags flags = kSecCSSigningInformation | kSecCSRequirementInformation | kSecCSDynamicInformation | kSecCSContentInformation;
    if (SecCodeCopySigningInformation(code, flags, &signingInfo) == noErr) {
        NSDictionary* signingDict = (NSDictionary*)signingInfo;
        NSMutableDictionary* relevantInfo = [NSMutableDictionary dictionary];
        for (NSString* key in @[@"format", @"identifier", @"requirements", @"teamid", @"signing-time"]) {
            relevantInfo[key] = signingDict[key];
        }
        NSDictionary* infoPlist = signingDict[@"info-plist"];
        relevantInfo[@"version"] = infoPlist[@"CFBundleShortVersionString"];
        relevantInfo[@"build"] = infoPlist[@"CFBundleVersion"];
        CFRelease(signingInfo);
        SULog(@"%@: %@", label, relevantInfo);
    }
}

+ (BOOL)hostApplicationIsCodeSigned
{
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

@end
