//
//  SUPlainInstaller.m
//  Sparkle
//
//  Created by Andy Matuschak on 4/10/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUPlainInstaller.h"
#import "SUPlainInstallerInternals.h"
#import "SUCodeSigningVerifier.h"
#import "SUConstants.h"
#import "SUHost.h"

@implementation SUPlainInstaller

+ (void)performInstallationToPath:(NSString *)installationPath fromPath:(NSString *)path host:(SUHost *)host versionComparator:(id<SUVersionComparison>)comparator completionHandler:(void (^)(NSError *))completionHandler
{
    SUParameterAssert(host);

    // Prevent malicious downgrades
    if (![[[NSBundle bundleWithIdentifier:SUBundleIdentifier] infoDictionary][SUEnableAutomatedDowngradesKey] boolValue]) {
        if ([comparator compareVersion:[host version] toVersion:[[NSBundle bundleWithPath:path] objectForInfoDictionaryKey:(__bridge NSString *)kCFBundleVersionKey]] == NSOrderedDescending) {
            NSString *errorMessage = [NSString stringWithFormat:@"Sparkle Updater: Possible attack in progress! Attempting to \"upgrade\" from %@ to %@. Aborting update.", [host version], [[NSBundle bundleWithPath:path] objectForInfoDictionaryKey:(__bridge NSString *)kCFBundleVersionKey]];
            NSError *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUDowngradeError userInfo:@{ NSLocalizedDescriptionKey: errorMessage }];
            [self finishInstallationToPath:installationPath withResult:NO error:error completionHandler:completionHandler];
            return;
        }
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        NSString *oldPath = [host bundlePath];
        NSString *tempName = [self temporaryNameForPath:[host installationPath]];

        BOOL result = [self copyPathWithAuthentication:path overPath:installationPath temporaryName:tempName error:&error];
        
        if (result) {
            if ([SUCodeSigningVerifier applicationAtPathIsCodeSigned:installationPath]) {
                result = [SUCodeSigningVerifier codeSignatureIsValidAtPath:installationPath error:&error];
            }
        }

        if (result) {
            BOOL haveOld = [[NSFileManager defaultManager] fileExistsAtPath:oldPath];
            BOOL differentFromNew = ![oldPath isEqualToString:installationPath];
            if (haveOld && differentFromNew) {
                [self _movePathToTrash:oldPath];    // On success, trash old copy if there's still one due to renaming.
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self finishInstallationToPath:installationPath withResult:result error:error completionHandler:completionHandler];
        });
    });
}

@end
