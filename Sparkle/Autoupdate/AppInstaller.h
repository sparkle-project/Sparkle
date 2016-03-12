//
//  AppInstaller.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/7/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "SUUnarchiver.h"

@interface AppInstaller : NSObject <SUUnarchiverDelegate>

- (instancetype)initWithHostPath:(NSString *)hostPath relaunchPath:(NSString *)relaunchPath hostProcessIdentifier:(NSNumber *)hostProcessIdentifier updateFolderPath:(NSString *)updateFolderPath downloadPath:(NSString *)downloadPath dsaSignature:(NSString *)dsaSignature;

- (void)extractAndInstallUpdate;

@end
