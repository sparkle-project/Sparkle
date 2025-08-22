//
//  SUCodeSigningVerifier.h
//  Sparkle
//
//  Created by Andy Matuschak on 7/5/12.
//
//

#ifndef SUCODESIGNINGVERIFIER_H
#define SUCODESIGNINGVERIFIER_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#ifndef BUILDING_SPARKLE_TESTS
#define SUCodeSigningVerifierDefinitionAttribute SPU_OBJC_DIRECT_MEMBERS
#else
#define SUCodeSigningVerifierDefinitionAttribute __attribute__((objc_runtime_name("SUTestCodeSigningVerifier")))
#endif

typedef NS_ENUM(NSUInteger, SUValidateConnectionStatus) {
    SUValidateConnectionStatusSetCodeSigningRequirementSuccess = 0,
    SUValidateConnectionStatusSetNoRequirementSuccess,
    SUValidateConnectionStatusAPIFailure,
    SUValidateConnectionStatusCodeSigningRequirementFailure,
    SUValidateConectionNoSupportedValidationMethodFailure,
};

typedef NS_OPTIONS(NSUInteger, SUValidateConnectionOptions) {
    // Default validation behavior (matches against Team ID from main executable if available)
    SUValidateConnectionOptionDefault = 0,
    
    // Require that the connecting client has the app sandbox entitlement
    SUValidateConnectionOptionRequireSandboxEntitlement = 1 << 0,
};

SUCodeSigningVerifierDefinitionAttribute
@interface SUCodeSigningVerifier : NSObject

+ (BOOL)codeSignatureIsValidAtBundleURL:(NSURL *)newBundleURL andMatchesSignatureAtBundleURL:(NSURL *)oldBundleURL error:(NSError **)error;

+ (BOOL)codeSignatureIsValidAtBundleURL:(NSURL *)bundleURL checkNestedCode:(BOOL)checkNestedCode error:(NSError **)error;

// Same as above except does not check for nested code. This method should be used by the framework.
+ (BOOL)codeSignatureIsValidAtBundleURL:(NSURL *)bundleURL error:(NSError *__autoreleasing *)error;

+ (BOOL)codeSignatureIsValidAtDownloadURL:(NSURL *)downloadURL andMatchesDeveloperIDTeamFromOldBundleURL:(NSURL *)oldBundleURL error:(NSError * __autoreleasing *)error;

+ (BOOL)bundleAtURLIsCodeSigned:(NSURL *)bundleURL;

+ (NSString * _Nullable)teamIdentifierAtURL:(NSURL *)url;
+ (NSString * _Nullable)teamIdentifierFromMainExecutable;

+ (SUValidateConnectionStatus)validateConnection:(NSXPCConnection *)connection options:(SUValidateConnectionOptions)options error:(NSError * __autoreleasing *)error;

@end

NS_ASSUME_NONNULL_END

#endif
