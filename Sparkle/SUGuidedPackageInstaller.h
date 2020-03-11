//
//  SUGuidedPackageInstaller.h
//  Sparkle
//
//  Created by Graham Miln on 14/05/2010.
//  Copyright 2010 Dragon Systems Software Limited. All rights reserved.
//

/*!
# Sparkle Guided Installations

A guided installation allows Sparkle to download and install a package (pkg) or multi-package (mpkg) without user interaction.

The installer package is installed using macOS's built-in command line installer, `/usr/sbin/installer`. No installation interface is shown to the user.

A guided installation can be started by applications other than the application being replaced. This is particularly useful where helper applications or agents are used.

## To Do
- Replace the use of `AuthorizationExecuteWithPrivilegesAndWait`. This method remains because it is well supported and tested. Ideally a helper tool or XPC would be used.
*/

#import <Foundation/Foundation.h>
#import "SUInstallerProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@interface SUGuidedPackageInstaller : NSObject <SUInstallerProtocol>

- (instancetype)initWithPackagePath:(NSString *)packagePath installationPath:(NSString *)installationPath fileOperationToolPath:(NSString *)fileOperationToolPath;

@end

NS_ASSUME_NONNULL_END
