//
//  SUInstaller.h
//  Sparkle
//
//  Created by Andy Matuschak on 4/10/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUInstallerProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@class SUHost;

@interface SUInstaller : NSObject

+ (nullable id<SUInstallerProtocol>)installerForHost:(SUHost *)host expectedInstallationType:(NSString *)expectedInstallationType updateDirectory:(NSString *)updateDirectory homeDirectory:(NSString *)homeDirectory userName:(NSString *)userName error:(NSError **)error;

+ (nullable NSString *)installSourcePathInUpdateFolder:(NSString *)inUpdateFolder forHost:(SUHost *)host isPackage:(BOOL *)isPackagePtr isGuided:(nullable BOOL *)isGuidedPtr;

@end

NS_ASSUME_NONNULL_END
