//
//  SUInstaller.h
//  Sparkle
//
//  Created by Andy Matuschak on 4/10/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface SUInstaller : NSObject { }
+ (void)installFromUpdateFolder:(NSString *)updateFolder overHostBundle:(NSBundle *)hostBundle delegate:delegate;
+ (void)_finishInstallationWithResult:(BOOL)result hostBundle:(NSBundle *)hostBundle error:(NSError *)error delegate:delegate;
@end

@interface NSObject (SUInstallerDelegateInformalProtocol)
- installerFinishedForHostBundle:(NSBundle *)hostBundle;
- installerForHostBundle:(NSBundle *)hostBundle failedWithError:(NSError *)error;
@end

extern NSString *SUInstallerPathKey;
extern NSString *SUInstallerHostBundleKey;
extern NSString *SUInstallerDelegateKey;
