//
//  SPUUpdatePermission.h
//  Sparkle
//
//  Created by Mayur Pawashe on 2/8/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUExport.h"

typedef NS_ENUM(NSInteger, SPUCheckUpdatesChoice) {
    SUAutomaticallyCheck,
    SUDoNotAutomaticallyCheck
};

SU_EXPORT @interface SPUUpdatePermission : NSObject<NSSecureCoding>

+ (instancetype)updatePermissionWithChoice:(SPUCheckUpdatesChoice)choice sendProfile:(BOOL)sendProfile;

@property (nonatomic, readonly) SPUCheckUpdatesChoice choice;
@property (nonatomic, readonly) BOOL sendProfile;

@end
