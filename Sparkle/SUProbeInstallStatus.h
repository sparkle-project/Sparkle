//
//  SUProbeInstallStatus.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/20/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SUHost, SUInstallationInfo;

@interface SUProbeInstallStatus : NSObject

+ (void)probeInstallerInProgressForHost:(SUHost *)host completion:(void (^)(BOOL))completionHandler;

// completionHandler may not be sent on main queue
// additionally, it may be possible that the installer is in progress but we get a nil installation info back
+ (void)probeInstallerUpdateItemForHost:(SUHost *)host completion:(void (^)(SUInstallationInfo  * _Nullable))completionHandler;

@end

NS_ASSUME_NONNULL_END
