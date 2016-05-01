//
//  SUUpdatePermission.h
//  Sparkle
//
//  Created by Mayur Pawashe on 2/8/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUExport.h"

typedef NS_ENUM(NSInteger, SUCheckUpdatesChoice) {
    SUAutomaticallyCheck,
    SUDoNotAutomaticallyCheck
};

SU_EXPORT @interface SUUpdatePermission : NSObject<NSSecureCoding>

+ (instancetype)updatePermissionWithChoice:(SUCheckUpdatesChoice)choice sendProfile:(BOOL)sendProfile;

@property (nonatomic, readonly) SUCheckUpdatesChoice choice;
@property (nonatomic, readonly) BOOL sendProfile;

@end
