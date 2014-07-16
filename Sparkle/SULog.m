/*
 *  SULog.m
 *  EyeTV
 *
 *  Created by Uli Kusterer on 12/03/2009.
 *  Copyright 2009 Elgato Systems GmbH. All rights reserved.
 *
 */

// -----------------------------------------------------------------------------
//	Headers:
// -----------------------------------------------------------------------------

#include "SULog.h"


// -----------------------------------------------------------------------------
//	Constants:
// -----------------------------------------------------------------------------

#define LOG_FILE_PATH @"~/Library/Logs/SparkleUpdateLog.log"


// -----------------------------------------------------------------------------
//	SUClearLog:
//		Erase the log at the start of an update. We don't want to litter the
//		user's hard disk with logging data that's mostly unused, so each app
//		should clear the log before it starts updating, so only the most recent
//		update is kept around.
//
//	TAKES:
//		sender	-	Object that sent this message, typically of type X.
//
//	GIVES:
//		param	-	who owns the returned value?
//		result	-	same here.
// -----------------------------------------------------------------------------

void SUClearLog(void)
{
    FILE *logfile = fopen([[LOG_FILE_PATH stringByExpandingTildeInPath] fileSystemRepresentation], "w");
    if (logfile)
        fclose(logfile);
    else
        NSLog(@"----- Sparkle Log -----");
}


// -----------------------------------------------------------------------------
//	SULog:
//		Like NSLog, but logs to one specific log file. Each line is prefixed
//		with the current date and time, to help in regressing issues.
//
//	TAKES:
//		format	-	NSLog/printf-style format string.
//		...		-	More parameters depending on format string's contents.
// -----------------------------------------------------------------------------

void SULog(NSString *format, ...)
{
    va_list ap;
    va_start(ap, format);
    NSString *theStr = [[NSString alloc] initWithFormat:format arguments:ap];
    FILE *logfile = fopen([[LOG_FILE_PATH stringByExpandingTildeInPath] fileSystemRepresentation], "a");
    if (!logfile)
        NSLog(@"%@", theStr);
	else
	{
        theStr = [NSString stringWithFormat:@"%@: %@", [NSDate date], theStr];
        NSData *theData = [theStr dataUsingEncoding:NSUTF8StringEncoding];
        char newlineChar = '\n';
        fwrite([theData bytes], 1, [theData length], logfile);
        fwrite(&newlineChar, 1, 1, logfile); // Append a newline.
        fclose(logfile);
        logfile = NULL;
    }
    va_end(ap);
}


