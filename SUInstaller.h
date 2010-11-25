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
@interface SUInstaller : NSObject { }
+ (void)installFromUpdateFolder:(NSString *)updateFolder overHost:(SUHost *)host delegate:delegate synchronously:(BOOL)synchronously versionComparator:(id <SUVersionComparison>)comparator;
+ (void)finishInstallationWithResult:(BOOL)result host:(SUHost *)host error:(NSError *)error delegate:delegate;
@end

@interface NSObject (SUInstallerDelegateInformalProtocol)
- (void)installerFinishedForHost:(SUHost *)host;
- (void)installerForHost:(SUHost *)host failedWithError:(NSError *)error;
@end

#endif
