//
//  SUInstaller.h
//  Sparkle
//
//  Created by Andy Matuschak on 4/10/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#ifndef SUINSTALLER_H
#define SUINSTALLER_H

#import <Cocoa/Cocoa.h>
#import "SUVersionComparisonProtocol.h"

@class SUHost;
@interface SUInstaller : NSObject

+ (NSString *)installSourcePathInUpdateFolder:(NSString *)inUpdateFolder forHost:(SUHost *)host isPackage:(BOOL *)isPackagePtr isGuided:(BOOL *)isGuidedPtr;
+ (void)installFromUpdateFolder:(NSString *)updateFolder overHost:(SUHost *)host installationPath:(NSString *)installationPath versionComparator:(id<SUVersionComparison>)comparator completionHandler:(void (^)(NSError *))completionHandler;
+ (void)finishInstallationToPath:(NSString *)installationPath withResult:(BOOL)result error:(NSError *)error completionHandler:(void (^)(NSError *))completionHandler;
+ (NSString *)updateFolder;

@end

#endif
