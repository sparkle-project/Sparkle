//
//  SUGuidedPackageInstaller.h
//  Sparkle
//
//  Created by Graham Miln on 14/05/2010.
//  Copyright 2010 Dragon Systems Software Limited. All rights reserved.
//

#ifndef SUGUIDEDPACKAGEINSTALLER_H
#define SUGUIDEDPACKAGEINSTALLER_H

#import "Sparkle.h"
#import "SUInstaller.h"

extern NSString* SUInstallerGuidedInstallerFilename; // default filename for guided installer property list

@interface SUGuidedPackageInstaller : SUInstaller { }
+ (void)performInstallationToPath:(NSString *)path fromPath:(NSString *)installerGuide host:(SUHost *)host delegate:delegate synchronously:(BOOL)synchronously versionComparator:(id <SUVersionComparison>)comparator;
@end

#endif
