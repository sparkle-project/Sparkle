//
//  SUPackageInstaller.h
//  Sparkle
//
//  Created by Andy Matuschak on 4/10/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SPUInstallerProtocol.h"

@interface SUPackageInstaller : NSObject <SPUInstallerProtocol>

- (instancetype)initWithPackagePath:(NSString *)packagePath;

@end
