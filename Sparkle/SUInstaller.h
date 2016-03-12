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

@protocol SUInstaller <NSObject>

- (instancetype)initWithHost:(SUHost *)host sourcePath:(NSString *)sourcePath installationPath:(NSString *)installationPath versionComparator:(id <SUVersionComparison>)comparator;

- (BOOL)startInstallation:(NSError **)error;

- (BOOL)resumeInstallation:(NSError **)error;

- (void)cleanup;

@end

@interface SUInstaller : NSObject

+ (nullable id<SUInstaller>)installerForHost:(SUHost *)host updateDirectory:(NSString *)updateDirectory versionComparator:(id <SUVersionComparison>)comparator error:(NSError **)error;

+ (NSString *)installSourcePathInUpdateFolder:(NSString *)inUpdateFolder forHost:(SUHost *)host isPackage:(BOOL *)isPackagePtr isGuided:(nullable BOOL *)isGuidedPtr;

+ (void)mdimportInstallationPath:(NSString *)installationPath;

@end

NS_ASSUME_NONNULL_END
