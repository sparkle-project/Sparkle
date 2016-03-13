//
//  SUPackageInstaller.h
//  Sparkle
//
//  Created by Andy Matuschak on 4/10/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUInstallerProtocol.h"

@interface SUPackageInstaller : NSObject <SUInstaller>

- (instancetype)initWithPackagePath:(NSString *)packagePath;

@end
