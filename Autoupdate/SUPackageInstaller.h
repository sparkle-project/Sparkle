//
//  SUPackageInstaller.h
//  Sparkle
//
//  Created by Andy Matuschak on 4/10/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#if SPARKLE_BUILD_PACKAGE_SUPPORT

#import <Foundation/Foundation.h>
#import "SUInstallerProtocol.h"

// This is the deprecated package installation type, aka the "interactive" package installer
// For a more supported package installation, see SUGuidedPackageInstaller

SPU_OBJC_DIRECT_MEMBERS @interface SUPackageInstaller : NSObject <SUInstallerProtocol>

- (instancetype)initWithPackagePath:(NSString *)packagePath;

@end

#endif
