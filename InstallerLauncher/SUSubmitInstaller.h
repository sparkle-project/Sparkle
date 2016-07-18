//
//  SUSubmitInstaller.h
//  Sparkle
//
//  Created by Mayur Pawashe on 7/17/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUAuthorizationReply.h"

NS_ASSUME_NONNULL_BEGIN

@interface SUSubmitInstaller : NSObject

+ (SUAuthorizationReply)submitInstallerAtPath:(NSString *)installerPath withHostBundle:(NSBundle *)hostBundle allowingInteraction:(BOOL)allowingInteraction inSystemDomain:(BOOL)systemDomain;

@end

NS_ASSUME_NONNULL_END
