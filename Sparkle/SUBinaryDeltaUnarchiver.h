//
//  SUBinaryDeltaUnarchiver.h
//  Sparkle
//
//  Created by Mark Rowe on 2009-06-03.
//  Copyright 2009 Mark Rowe. All rights reserved.
//

#ifndef SUBINARYDELTAUNARCHIVER_H
#define SUBINARYDELTAUNARCHIVER_H

#import <Foundation/Foundation.h>
#import "SUUnarchiverProtocol.h"

@interface SUBinaryDeltaUnarchiver : NSObject <SUUnarchiver>

- (instancetype)initWithArchivePath:(NSString *)archivePath updateHostBundlePath:(NSString *)updateHostBundlePath delegate:(id <SUUnarchiverDelegate>)delegate;

@end

#endif
