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

@protocol SUInstallerDelegate;

@class SUHost;
@interface SUInstaller : NSObject

+ (NSString *)appPathInUpdateFolder:(NSString *)updateFolder forHost:(SUHost *)host;
+ (void)installFromUpdateFolder:(NSString *)updateFolder overHost:(SUHost *)host installationPath:(NSString *)installationPath delegate:(id<SUInstallerDelegate>)delegate versionComparator:(id<SUVersionComparison>)comparator;
+ (void)finishInstallationToPath:(NSString *)installationPath withResult:(BOOL)result host:(SUHost *)host error:(NSError *)error delegate:(id<SUInstallerDelegate>)delegate;
+ (NSString *)updateFolder;

@end

@protocol SUInstallerDelegate <NSObject>
- (void)installerFinishedForHost:(SUHost *)host;
- (void)installerForHost:(SUHost *)host failedWithError:(NSError *)error;
@end

#endif
