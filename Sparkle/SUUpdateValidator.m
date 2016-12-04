//
//  SUUpdateValidator.m
//  Sparkle
//
//  Created by Mayur Pawashe on 12/3/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUUpdateValidator.h"
#import "SPUInstallerValidation.h"
#import "SUInstaller.h"
#import "SUHost.h"
#import "SULog.h"

@interface SUUpdateValidator ()

@property (nonatomic, readonly) SUHost *host;
@property (nonatomic, readonly) BOOL prevalidatedDsaSignature;
@property (nonatomic, readonly) NSString *dsaSignature;
@property (nonatomic, readonly) NSString *downloadPath;

@end

@implementation SUUpdateValidator

@synthesize host = _host;
@synthesize canValidate = _canValidate;
@synthesize prevalidatedDsaSignature = _prevalidatedDsaSignature;
@synthesize dsaSignature = _dsaSignature;
@synthesize downloadPath = _downloadPath;

- (instancetype)initWithDownloadPath:(NSString *)downloadPath dsaSignature:(NSString *)dsaSignature host:(SUHost *)host performingPrevalidation:(BOOL)performingPrevalidation
{
    self = [super init];
    if (self != nil) {
        BOOL canValidate;
        BOOL prevalidatedDsaSignature;
        if (performingPrevalidation) {
            NSString *publicDSAKey = host.publicDSAKey;
            
            if (publicDSAKey == nil) {
                prevalidatedDsaSignature = NO;
                SULog(@"Failed to validate update before unarchiving because no DSA key was found");
            } else if (dsaSignature == nil) {
                prevalidatedDsaSignature = NO;
                SULog(@"Failed to validate update before unarchiving because no DSA signature was found");
            } else {
                prevalidatedDsaSignature = [SPUInstallerValidation validateUpdateForHost:host archivePath:downloadPath DSASignature:dsaSignature];
                if (!prevalidatedDsaSignature) {
                    SULog(@"DSA signature validation before unarchiving failed for update %@", downloadPath);
                }
            }
            
            canValidate = prevalidatedDsaSignature;
        } else {
            prevalidatedDsaSignature = NO;
            canValidate = YES;
        }
        
        _canValidate = canValidate;
        _prevalidatedDsaSignature = prevalidatedDsaSignature;
        _downloadPath = [downloadPath copy];
        _dsaSignature = [dsaSignature copy];
        _host = host;
    }
    return self;
}

- (BOOL)validateWithUpdateDirectory:(NSString *)updateDirectory
{
    assert(self.canValidate);
    
    NSString *DSASignature = self.dsaSignature;
    NSString *downloadPath = self.downloadPath;
    SUHost *host = self.host;
    
    BOOL prevalidatedDsaSignature = self.prevalidatedDsaSignature;
    
    BOOL validationCheckSuccess;
    BOOL isPackage = NO;
    
    // install source could point to a new bundle or a package
    NSString *installSource = [SUInstaller installSourcePathInUpdateFolder:updateDirectory forHost:host isPackage:&isPackage isGuided:NULL];
    if (installSource == nil) {
        SULog(@"No suitable install is found in the update. The update will be rejected.");
        validationCheckSuccess = NO;
    } else {
        NSURL *installSourceURL = [NSURL fileURLWithPath:installSource];
        
        if (!prevalidatedDsaSignature) {
            // Check to see if we have a package or bundle to validate
            if (isPackage) {
                // If we get here, then the appcast installation type was lying to us.. This error will be caught later when starting the installer.
                // For package type updates, all we do is check if the DSA signature is valid
                validationCheckSuccess = [SPUInstallerValidation validateUpdateForHost:host archivePath:downloadPath DSASignature:DSASignature];
                
                if (!validationCheckSuccess) {
                    SULog(@"DSA signature validation of the package failed. The update contains an installer package, and valid DSA signatures are mandatory for all installer packages. The update will be rejected. Sign the installer with a valid DSA key or use an .app bundle update instead.");
                }
            } else {
                // For application bundle updates, validate the bundle code signatures and DSA signatures of archive together
                validationCheckSuccess = [SPUInstallerValidation validateBundleUpdateForHost:host newBundleURL:installSourceURL archivePath:downloadPath DSASignature:DSASignature];
            }
        } else if (isPackage) {
            // We already prevalidated the package and nothing else needs to be done
            validationCheckSuccess = YES;
        } else {
            // Because we already prevalidated the DSA signature, this is just a consistency check to see
            // if the developer signed their application properly with their Apple ID
            // Currently, this case only gets hit for binary delta updates
            validationCheckSuccess = [SPUInstallerValidation validateCodeSignatureIfAvailableForBundleURL:installSourceURL];
        }
    }
    
    return validationCheckSuccess;
}

@end
