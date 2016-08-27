//
//  SUPackageInstaller.h
//  Sparkle
//
//  Created by Andy Matuschak on 4/10/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SPUInstallerProtocol.h"

// This is the deprecated package installation type, aka the "interactive" package installer
// For a more supported package installation, see SUGuidedPackageInstaller

@interface SUPackageInstaller : NSObject <SPUInstallerProtocol>

- (instancetype)initWithPackagePath:(NSString *)packagePath installationPath:(NSString *)installationPath;

@end
