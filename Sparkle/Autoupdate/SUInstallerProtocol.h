//
//  SUInstallerProtocol.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/12/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol SUInstaller <NSObject>

// Stage 1 is where any installation work can be done prior to user application being terminated and relaunched
// No UI should occur during this stage (i.e, do not prompt for authorization prompts, show package installer apps, etc..)
// Should be able to be called from non-main thread
- (BOOL)performFirstStage:(NSError **)error;

// Stage 2 is where any further installation work can be done prior to the user application being terminated
// The allowsUI flag indicates whether this stage can show UI or not, possibly affecting whether or not this stage succeeds.
// Eg: This may be appropriate for first showing an authorization prompt before the user application is terminated (if the operation succeeds)
// Should be able to be called from non-main thread
- (BOOL)performSecondStageAllowingUI:(BOOL)allowsUI error:(NSError **)error;

// Stage 3 occurs after the user application has has been terminated. This is where the final installation work can be done.
// After this stage is done, the user application will be relaunched.
// Should be able to be called from non-main thread
- (BOOL)performThirdStage:(NSError **)error;

// Indicates whether or not this installer will show the user visible installation progress
- (BOOL)displaysUserProgress;

// Cleans up work done from any of the previous stages. This should be invoked after stage 3 succeeds,
// or after any one of the stages fails.
// Should be able to be called from non-main thread
- (void)cleanup;

@end
