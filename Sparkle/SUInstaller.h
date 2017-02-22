//
//  SUInstaller.h
//  Sparkle
//
//  Created by Andy Matuschak on 4/10/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUVersionComparisonProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@class SUHost;

@protocol SUInstallerProtocol;

@interface SUInstaller : NSObject

+ (nullable id<SUInstallerProtocol>)installerForHost:(SUHost *)host fileOperationToolPath:(NSString *)fileOperationToolPath updateDirectory:(NSString *)updateDirectory error:(NSError **)error;

+ (nullable NSString *)installSourcePathInUpdateFolder:(NSString *)inUpdateFolder forHost:(SUHost *)host isPackage:(BOOL *)isPackagePtr isGuided:(nullable BOOL *)isGuidedPtr;

@end

NS_ASSUME_NONNULL_END
