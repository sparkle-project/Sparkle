//
//  SUInstallerLauncherProtocol.h
//  InstallerLauncher
//
//  Created by Mayur Pawashe on 4/1/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol SUInstallerLauncherProtocol

- (void)launchInstallerAtPath:(NSString *)installerPath withHostBundleIdentifier:(NSString *)hostBundleIdentifier allowingInteraction:(BOOL)allowingInteraction completion:(void (^)(BOOL success))completionHandler;
    
@end
