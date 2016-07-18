//
//  SUInstallerLauncherProtocol.h
//  InstallerLauncher
//
//  Created by Mayur Pawashe on 4/1/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUAuthorizationReply.h"

@protocol SUInstallerLauncherProtocol

- (void)launchInstallerAtPath:(NSString *)installerPath progressToolPath:(NSString *)progressToolPath withHostBundlePath:(NSString *)hostBundlePath guidedInstallation:(BOOL)guidedInstallation allowingInteraction:(BOOL)allowingInteraction completion:(void (^)(SUAuthorizationReply))completionHandler;
    
@end
