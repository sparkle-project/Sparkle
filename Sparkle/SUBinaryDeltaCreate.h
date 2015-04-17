//
//  SUBinaryDeltaCreate.m
//  Sparkle
//
//  Created by Mayur Pawashe on 4/9/15.
//  Copyright (c) 2015 Sparkle Project. All rights reserved.
//

#ifndef SUBINARYDELTACREATE_H
#define SUBINARYDELTACREATE_H

@class NSString;
int createBinaryDelta(NSString *source, NSString *destination, NSString *patchFile, uint16_t majorVersion);

#endif
