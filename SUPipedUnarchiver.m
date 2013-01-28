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
		typeSelectorDictionary = [[NSDictionary dictionaryWithObjectsAndKeys:@"extractZIP", @".zip", @"extractTAR", @".tar",
								   @"extractTGZ", @".tar.gz", @"extractTGZ", @".tgz",
								   @"extractTBZ", @".tar.bz2", @"extractTBZ", @".tbz", nil] retain];

	NSString *lastPathComponent = [path lastPathComponent];
	NSEnumerator *typeEnumerator = [typeSelectorDictionary keyEnumerator];
	id currentType;
	while ((currentType = [typeEnumerator nextObject]))
	{
		if ([currentType length] > [lastPathComponent length]) continue;
		if ([[lastPathComponent substringFromIndex:[lastPathComponent length] - [currentType length]] isEqualToString:currentType])
			return NSSelectorFromString([typeSelectorDictionary objectForKey:currentType]);
	}
	return NULL;
}

- (void)start
{
	[NSThread detachNewThreadSelector:[[self class] selectorConformingToTypeOfPath:archivePath] toTarget:self withObject:nil];
}

+ (BOOL)canUnarchivePath:(NSString *)path
{
	return ([self selectorConformingToTypeOfPath:path] != nil);
}

// This method abstracts the types that use a command line tool piping data from stdin.
- (void)extractArchivePipingDataToCommand:(NSString *)command
{
	// *** GETS CALLED ON NON-MAIN THREAD!!!
	

	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	FILE *fp = NULL, *cmdFP = NULL;
	char *oldDestinationString = NULL;
	
	SULog(@"Extracting %@ using '%@'",archivePath,command);
    
	// Get the file size.
#if MAC_OS_X_VERSION_MIN_REQUIRED <= MAC_OS_X_VERSION_10_4
	NSNumber *fs = [[[NSFileManager defaultManager] fileAttributesAtPath:archivePath traverseLink:NO] objectForKey:NSFileSize];
#else
	NSNumber *fs = [[[NSFileManager defaultManager] attributesOfItemAtPath:archivePath error:nil] objectForKey:NSFileSize];
#endif
	if (fs == nil) goto reportError;
	
	// Thank you, Allan Odgaard!
	// (who wrote the following extraction alg.)
	fp = fopen([archivePath fileSystemRepresentation], "r");
	if (!fp) goto reportError;
	
    oldDestinationString = getenv("DESTINATION");
	setenv("DESTINATION", [[archivePath stringByDeletingLastPathComponent] fileSystemRepresentation], 1);
	cmdFP = popen([command fileSystemRepresentation], "w");
	size_t written;
	if (!cmdFP) goto reportError;
	
	char buf[32*1024];
	size_t len;
	while((len = fread(buf, 1, 32*1024, fp)))
	{				
		written = fwrite(buf, 1, len, cmdFP);
		if( written < len )
		{
			pclose(cmdFP);
			goto reportError;
		}
			
		[self performSelectorOnMainThread:@selector(notifyDelegateOfExtractedLength:) withObject:[NSNumber numberWithUnsignedLong:len] waitUntilDone:NO];
	}
	pclose(cmdFP);
	
	if( ferror( fp ) )
		goto reportError;
	
	[self performSelectorOnMainThread:@selector(notifyDelegateOfSuccess) withObject:nil waitUntilDone:NO];
	goto finally;
	
reportError:
	[self performSelectorOnMainThread:@selector(notifyDelegateOfFailure) withObject:nil waitUntilDone:NO];
	
finally:
	if (fp)
		fclose(fp);
    if (oldDestinationString)
        setenv("DESTINATION", oldDestinationString, 1);
    else
        unsetenv("DESTINATION");
	[pool release];
}

- (void)extractTAR
{
	// *** GETS CALLED ON NON-MAIN THREAD!!!
	
	return [self extractArchivePipingDataToCommand:@"tar -xC \"$DESTINATION\""];
}

- (void)extractTGZ
{
	// *** GETS CALLED ON NON-MAIN THREAD!!!
	
	return [self extractArchivePipingDataToCommand:@"tar -zxC \"$DESTINATION\""];
}

- (void)extractTBZ
{
	// *** GETS CALLED ON NON-MAIN THREAD!!!
	
	return [self extractArchivePipingDataToCommand:@"tar -jxC \"$DESTINATION\""];
}

- (void)extractZIP
{
	// *** GETS CALLED ON NON-MAIN THREAD!!!
	
	return [self extractArchivePipingDataToCommand:@"ditto -x -k - \"$DESTINATION\""];
}

+ (void)load
{
	[self registerImplementation:self];
}

@end
