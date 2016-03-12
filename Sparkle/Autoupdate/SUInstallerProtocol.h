//
//  SUInstallerProtocol.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/12/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol SUVersionComparison;
@class SUHost;

@protocol SUInstaller <NSObject>

- (instancetype)initWithHost:(SUHost *)host sourcePath:(NSString *)sourcePath installationPath:(NSString *)installationPath versionComparator:(id <SUVersionComparison>)comparator;

- (BOOL)startInstallation:(NSError **)error;

- (BOOL)resumeInstallation:(NSError **)error;

- (void)cleanup;

@end
