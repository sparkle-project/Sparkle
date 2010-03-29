//
//  SUCarbonUpdater.h
//  Sparkle
//
//  Created by Jack Small on 2/22/07.
//  Copyright 2007 Jack Small. All rights reserved.
//

#if SU_SPARKLE_FOR_CARBON

#import <Cocoa/Cocoa.h>
#import "SUUpdater.h"
#import "SUCarbonAPI.h"

@interface SUCarbonUpdater : SUUpdater
{
	EventTargetRef	carbonEventTarget;
}

// This utility method was added for Carbon applications to check if updates are running.
// It is called by SUSparkleIsUpdateInProgress().
- (BOOL)updateInProgress;

// This method changes the event target for this updater.  If set, a kEventSparkleFoundVersion
// event is sent when an appcast result is found, instead of a traditinal install.
- (id)setCarbonEventTarget:(EventTargetRef)statusEventTarget;

@end

#endif	//	SU_SPARKLE_FOR_CARBON

