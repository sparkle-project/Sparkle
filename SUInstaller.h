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

@interface SUInstaller : NSObject { }
+ (void)installFromUpdateFolder:(NSString *)updateFolder overHostBundle:(NSBundle *)hostBundle delegate:delegate synchronously:(BOOL)synchronously;
+ (void)_finishInstallationWithResult:(BOOL)result hostBundle:(NSBundle *)hostBundle error:(NSError *)error delegate:delegate;
@end

@interface NSObject (SUInstallerDelegateInformalProtocol)
- (void)installerFinishedForHostBundle:(NSBundle *)hostBundle;
- (void)installerForHostBundle:(NSBundle *)hostBundle failedWithError:(NSError *)error;
@end

#endif
