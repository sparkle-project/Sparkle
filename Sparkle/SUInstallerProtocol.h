//
//  SUInstallerProtocol.h
//  Sparkle
//
//  Created by Mayur Pawashe on 12/26/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SUInstallerProtocol <NSObject>

// Any installation work can be done prior to user application being terminated and relaunched
// Currently this is invoked after the user application is terminated, but this may change in the future.
// No UI should occur during this stage (i.e, do not show package installer apps, etc..)
// Should be able to be called from non-main thread
- (BOOL)performInitialInstallation:(NSError **)error;

// Any installation work after the user application has been terminated. This is where the final installation work can be done.
// After this stage is done, the user application may be relaunched.
// Should be able to be called from non-main thread
- (BOOL)performFinalInstallationProgressBlock:(nullable void(^)(double))cb error:(NSError **)error;

// Indicates whether or not this installer can install the update silently in the background, without hindering the user
// Should be thread safe
- (BOOL)canInstallSilently;

// The destination and installation path of the bundle being updated
// Should be thread safe
- (NSString *)installationPath;

@end

NS_ASSUME_NONNULL_END
