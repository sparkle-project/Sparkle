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

- (instancetype)initWithHost:(SUHost *)host applicationPath:(NSString *)applicationPath installationPath:(NSString *)installationPath versionComparator:(id <SUVersionComparison>)comparator;

@end
