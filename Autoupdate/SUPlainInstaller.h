//
//  SUPlainInstaller.h
//  Sparkle
//
//  Created by Andy Matuschak on 4/10/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SPUInstallerProtocol.h"

@class SUHost;
@protocol SUVersionComparison;

@interface SUPlainInstaller : NSObject <SPUInstallerProtocol>

/*!
 @param host The current (old) bundle host
 @param bundlePath The path to the new bundle that will be installed.
 @param installationPath The path the new bundlePath will be installed to.
 @param comparator The version comparator to use to prevent a downgrade from occurring.
 */
- (instancetype)initWithHost:(SUHost *)host bundlePath:(NSString *)bundlePath installationPath:(NSString *)installationPath versionComparator:(id <SUVersionComparison>)comparator;

@end
