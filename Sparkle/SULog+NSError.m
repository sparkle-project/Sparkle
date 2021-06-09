//
//  SULog+NSError.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/19/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#import "SULog+NSError.h"
#import "SULog.h"

#include "AppKitPrevention.h"

void SULogError(NSError *error)
{
    NSError *errorToDisplay = error;
    int finiteRecursion = 5;
    do {
        SULog(SULogLevelError, @"Error: %@ %@ (URL %@)", errorToDisplay.localizedDescription, errorToDisplay.localizedFailureReason, errorToDisplay.userInfo[NSURLErrorFailingURLErrorKey]);
        errorToDisplay = errorToDisplay.userInfo[NSUnderlyingErrorKey];
    } while(--finiteRecursion && errorToDisplay);
}
