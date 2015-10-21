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

#include "SUHost.h"


// -----------------------------------------------------------------------------
//	Constants:
// -----------------------------------------------------------------------------

static NSString *const SULogDefaultFilePath = @"~/Library/Logs/SparkleUpdateLog.log";
static NSString *const SULogFilePathTemplate = @"~/Library/Logs/SparkleUpdateLog-%@.log";

static unsigned long long MaxLogFileSize = 1 * 1024 * 1024; // 1MB default
static float TrimMaxFileSizeCoefficient = 0.75;
static BOOL EnableTraceLogging = NO;
static BOOL UsePersonalLogFile = NO;
static BOOL ClearAtLaunch = YES;

// -----------------------------------------------------------------------------
//	Private prototypes:
// -----------------------------------------------------------------------------

NSString *SULogFilePath(void);
NSString *SUCustomLogFilePath(void);

// -----------------------------------------------------------------------------
//	SUGetFilePath:
//		Returns the log file path
// -----------------------------------------------------------------------------

NSString *SULogFilePath(void)
{
    return UsePersonalLogFile ? SUCustomLogFilePath() : SULogDefaultFilePath;
}

// -----------------------------------------------------------------------------
//	SUCustomLogFilePath:
//		Returns a path, unique for the application, in the user's logs dir
// -----------------------------------------------------------------------------

NSString *SUCustomLogFilePath(void)
{
    static NSString *filePath = nil;
    if (filePath == nil) {
        filePath = [NSString stringWithFormat:SULogFilePathTemplate,
                    [[NSFileManager defaultManager] displayNameAtPath:[[NSBundle mainBundle] bundlePath]]];
    }
    return filePath;
}

// -----------------------------------------------------------------------------
//	SUClearLog:
//		Erase the log at the start of an update. We don't want to litter the
//		user's hard disk with logging data that's mostly unused, so each app
//		should clear the log before it starts updating, so only the most recent
//		update is kept around.
//
//	TAKES:
//		sender	-	Object that sent this message, typically of type X.
// -----------------------------------------------------------------------------

void SUClearLog(void)
{
    FILE *logfile = fopen([[SULogFilePath() stringByExpandingTildeInPath] fileSystemRepresentation], "w");
    if (logfile) {
        fclose(logfile);
        SULog(@"===== %@ =====", [[NSFileManager defaultManager] displayNameAtPath:[[NSBundle mainBundle] bundlePath]]);
    }
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
    static BOOL loggedYet = NO;
    if (!loggedYet) {
        loggedYet = YES;
        if (ClearAtLaunch) {
            SUClearLog();
        }
    }

    va_list ap;
    va_start(ap, format);
    NSString *theStr = [[NSString alloc] initWithFormat:format arguments:ap];
    NSLog(@"Sparkle: %@", theStr);

    FILE *logfile = fopen([[SULogFilePath() stringByExpandingTildeInPath] fileSystemRepresentation], "a");
    if (logfile) {
        theStr = [NSString stringWithFormat:@"%@: %@\n", [NSDate date], theStr];
        NSData *theData = [theStr dataUsingEncoding:NSUTF8StringEncoding];
        fwrite([theData bytes], 1, [theData length], logfile);
        fclose(logfile);
    }
    va_end(ap);
}

// -----------------------------------------------------------------------------
//	SULogTrace:
//		Same like SULog, but logs only when tracing option is enabled
//
//	TAKES:
//		format	-	NSLog/printf-style format string.
//		...		-	More parameters depending on format string's contents.
// -----------------------------------------------------------------------------

void SULogTrace(NSString *format, ...) {
    if (!EnableTraceLogging) {
        return;
    }
    va_list ap;
    va_start(ap, format);
    NSString *theStr = [[NSString alloc] initWithFormat:format arguments:ap];
    
    SULog(@"%@", theStr);
    
    va_end(ap);
}

// -----------------------------------------------------------------------------
//	SUMaybeTrimLogFile:
//      	Call this function to reduce log file size if it became bigger than
//		defined MaxLogFileSize constant. Data is reduced up to DesiredLogFileSize
//		and to the first character after its first new line character.
// -----------------------------------------------------------------------------

void SUMaybeTrimLogFile(void)
{
    NSString *logFilePath = [SULogFilePath() stringByExpandingTildeInPath];
    NSError *error = nil;
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:logFilePath]) {
        return;
    }
    
    unsigned long long logSize = [[[NSFileManager defaultManager] attributesOfItemAtPath:logFilePath
                                                                                   error:&error] fileSize];
    
    if (error != nil) {
        NSLog(@"%@", error);
        return;
    }
    
    if (logSize < MaxLogFileSize) {
        return;
    }
    
    // Read contents from the log file
    NSString *contents = [NSString stringWithContentsOfFile:logFilePath encoding:NSUTF8StringEncoding error:&error];
    if (error != nil) {
        NSLog(@"%@", error);
    }
    if (contents.length == 0) {
        return;
    }
    
    NSUInteger cropLength = (NSUInteger)((MaxLogFileSize * TrimMaxFileSizeCoefficient) * contents.length / logSize);
    if (contents.length < cropLength) {
        return;
    }
    
    // Trim to desired size
    NSString *newContents = [contents substringFromIndex:contents.length - cropLength];
    if (newContents.length == 0) {
        return;
    }
    // Trim to the first character after first new-line character, if possible
    NSRange firstNewLineRange = [newContents rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]];
    if (firstNewLineRange.location != NSNotFound && firstNewLineRange.location + 1 < newContents.length) {
        newContents = [newContents substringFromIndex:firstNewLineRange.location + 1];
    }
    
    // Save results to the file (overwrite)
    [newContents writeToFile:logFilePath atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (error != nil) {
        NSLog(@"%@", error);
    }
}

// -----------------------------------------------------------------------------
//	SULoadLogSettingsFromBundle:
//      	Loads logging settings from the given bundle
// -----------------------------------------------------------------------------

void SULoadLogSettingsFromBundle(NSBundle *bundle)
{
    SUHost *host = [[SUHost alloc] initWithBundle:bundle];
    if (host == nil) {
        return;
    }
    
    if ([host objectForKey:SULogTraceLoggingKey] != nil) {
        EnableTraceLogging = [host boolForKey:SULogTraceLoggingKey];
    }
    if ([host objectForKey:SULogPersonalLogFileKey] != nil) {
        UsePersonalLogFile = [host boolForKey:SULogPersonalLogFileKey];
    }
    if ([host objectForKey:SULogClearAtLaunchKey]) {
        ClearAtLaunch = [host boolForKey:SULogClearAtLaunchKey];
    }
    
    NSNumber *fileSizeValue = [host objectForKey:SULogMaxFileSizeKey];
    if (fileSizeValue != nil && [fileSizeValue isKindOfClass:[NSNumber class]]) {
        MaxLogFileSize = [[host objectForKey:SULogMaxFileSizeKey] unsignedLongLongValue];
    }
    
    NSNumber *trimCoefValue = [host objectForKey:SULogTrimMaxFileSizeCoefficientKey];
    if (trimCoefValue != nil && [trimCoefValue isKindOfClass:[NSNumber class]]) {
        TrimMaxFileSizeCoefficient = [trimCoefValue floatValue];
    }
}
