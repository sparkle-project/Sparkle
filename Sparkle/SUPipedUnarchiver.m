//
//  SUPipedUnarchiver.m
//  Sparkle
//
//  Created by Andy Matuschak on 6/16/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUPipedUnarchiver.h"
#import "SUUnarchiver_Private.h"
#import "SULog.h"


@implementation SUPipedUnarchiver

+ (SEL)selectorConformingToTypeOfPath:(NSString *)path
{
    static NSDictionary *typeSelectorDictionary;
    if (!typeSelectorDictionary)
        typeSelectorDictionary = @{ @".zip": @"extractZIP",
                                    @".tar": @"extractTAR",
                                    @".tar.gz": @"extractTGZ",
                                    @".tgz": @"extractTGZ",
                                    @".tar.bz2": @"extractTBZ",
                                    @".tbz": @"extractTBZ" };

    NSString *lastPathComponent = [path lastPathComponent];
	for (NSString *currentType in typeSelectorDictionary)
	{
		if ([currentType length] > [lastPathComponent length]) continue;
        if ([[lastPathComponent substringFromIndex:[lastPathComponent length] - [currentType length]] isEqualToString:currentType])
            return NSSelectorFromString(typeSelectorDictionary[currentType]);
    }
    return NULL;
}

- (void)start
{
    [NSThread detachNewThreadSelector:[[self class] selectorConformingToTypeOfPath:self.archivePath] toTarget:self withObject:nil];
}

+ (BOOL)canUnarchivePath:(NSString *)path
{
    return ([self selectorConformingToTypeOfPath:path] != nil);
}

// This method abstracts the types that use a command line tool piping data from stdin.
- (void)extractArchivePipingDataToCommand:(NSString *)command
{
    // *** GETS CALLED ON NON-MAIN THREAD!!!
	@autoreleasepool {
        FILE *fp = NULL, *cmdFP = NULL;
        char *oldDestinationString = NULL;
        // We have to declare these before a goto to prevent an error under ARC.
        // No, we cannot have them in the dispatch_async calls, as the goto "jump enters
        // lifetime of block which strongly captures a variable"
        dispatch_block_t delegateSuccess = ^{
            [self notifyDelegateOfSuccess];
        };
        dispatch_block_t delegateFailure = ^{
            [self notifyDelegateOfFailure];
        };

        SULog(@"Extracting %@ using '%@'", self.archivePath, command);

        // Get the file size.
        NSNumber *fs = [[NSFileManager defaultManager] attributesOfItemAtPath:self.archivePath error:nil][NSFileSize];
		if (fs == nil) goto reportError;

        // Thank you, Allan Odgaard!
        // (who wrote the following extraction alg.)
        fp = fopen([self.archivePath fileSystemRepresentation], "r");
		if (!fp) goto reportError;

        oldDestinationString = getenv("DESTINATION");
        setenv("DESTINATION", [[self.archivePath stringByDeletingLastPathComponent] fileSystemRepresentation], 1);
        cmdFP = popen([command fileSystemRepresentation], "w");
        size_t written;
		if (!cmdFP) goto reportError;

        char buf[32 * 1024];
        size_t len;
		while((len = fread(buf, 1, 32*1024, fp)))
		{
            written = fwrite(buf, 1, len, cmdFP);
			if( written < len )
			{
                pclose(cmdFP);
                goto reportError;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
				[self notifyDelegateOfExtractedLength:len];
            });
        }
        pclose(cmdFP);

        if (ferror(fp)) {
            goto reportError;
        }

        dispatch_async(dispatch_get_main_queue(), delegateSuccess);
        goto finally;

    reportError:
        dispatch_async(dispatch_get_main_queue(), delegateFailure);

    finally:
        if (fp)
            fclose(fp);
        if (oldDestinationString)
            setenv("DESTINATION", oldDestinationString, 1);
        else
            unsetenv("DESTINATION");
    }
}

- (void)extractTAR
{
    // *** GETS CALLED ON NON-MAIN THREAD!!!

    [self extractArchivePipingDataToCommand:@"tar -xC \"$DESTINATION\""];
}

- (void)extractTGZ
{
    // *** GETS CALLED ON NON-MAIN THREAD!!!

    [self extractArchivePipingDataToCommand:@"tar -zxC \"$DESTINATION\""];
}

- (void)extractTBZ
{
    // *** GETS CALLED ON NON-MAIN THREAD!!!

    [self extractArchivePipingDataToCommand:@"tar -jxC \"$DESTINATION\""];
}

- (void)extractZIP
{
    // *** GETS CALLED ON NON-MAIN THREAD!!!

    [self extractArchivePipingDataToCommand:@"ditto -x -k - \"$DESTINATION\""];
}

+ (void)load
{
    [self registerImplementation:self];
}

@end
