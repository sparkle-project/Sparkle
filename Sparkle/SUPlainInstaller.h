//
//  SUPlainInstaller.h
//  Sparkle
//
//  Created by Andy Matuschak on 4/10/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUInstallerProtocol.h"

@class SUHost;
@protocol SUVersionComparison;

@interface SUPlainInstaller : NSObject <SUInstaller>

- (instancetype)initWithHost:(SUHost *)host applicationPath:(NSString *)applicationPath installationPath:(NSString *)installationPath versionComparator:(id <SUVersionComparison>)comparator;

@end
