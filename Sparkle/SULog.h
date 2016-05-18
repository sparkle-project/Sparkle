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

// Logging utlity function that is thread-safe
// Please only use this for logging *error* messages
// More types of logging functions could be added in the future...
void SULog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

#endif
