//
//  SULog.h
//  Sparkle
//
//  Created by Mayur Pawashe on 5/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#ifndef SULOG_H
#define SULOG_H

#include <Foundation/Foundation.h>

typedef NS_ENUM(uint8_t, SULogLevel) {
    SULogLevelDefault = 0,
    SULogLevelError = 1
};

// Logging utlity function that is thread-safe
// On 10.12 or later this uses os_log
// Otherwise on older systems this uses ASL
void SULog(SULogLevel level, NSString *format, ...) NS_FORMAT_FUNCTION(2, 3);

#endif
