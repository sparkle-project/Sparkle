//
//  SUPipedUnarchiver.m
//  Sparkle
//
//  Created by Andy Matuschak on 6/16/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUPipedUnarchiver.h"
#import "SUUnarchiver_Private.h"

@implementation SUPipedUnarchiver

+ (SEL)_selectorConformingToTypeOfPath:(NSString *)path
{
	static NSDictionary *typeSelectorDictionary;
	if (!typeSelectorDictionary)
		typeSelectorDictionary = [[NSDictionary dictionaryWithObjectsAndKeys:@"_extractZIP", @".zip", @"_extractTAR", @".tar",
								   @"_extractTGZ", @".tar.gz", @"_extractTGZ", @".tgz",
								   @"_extractTBZ", @".tar.bz2", @"_extractTBZ", @".tbz", nil] retain];

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
	[NSThread detachNewThreadSelector:[[self class] _selectorConformingToTypeOfPath:archivePath] toTarget:self withObject:nil];
}

+ (BOOL)_canUnarchivePath:(NSString *)path
{
	return ([self _selectorConformingToTypeOfPath:path] != nil);
}

// This method abstracts the types that use a command line tool piping data from stdin.
- (void)_extractArchivePipingDataToCommand:(NSString *)command
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	FILE *fp = NULL, *cmdFP = NULL;
	
	// Get the file size.
	NSNumber *fs = [[[NSFileManager defaultManager] fileAttributesAtPath:archivePath traverseLink:NO] objectForKey:NSFileSize];
	if (fs == nil) goto reportError;
	
	// Thank you, Allan Odgaard!
	// (who wrote the following extraction alg.)
	fp = fopen([archivePath fileSystemRepresentation], "r");
	if (!fp) goto reportError;
	
	setenv("DESTINATION", [[archivePath stringByDeletingLastPathComponent] fileSystemRepresentation], 1);
	cmdFP = popen([command fileSystemRepresentation], "w");
	if (!cmdFP) goto reportError;
	
	char buf[32*1024];
	long len;
	while((len = fread(buf, 1, 32*1024, fp)))
	{				
		fwrite(buf, 1, len, cmdFP);
		[self performSelectorOnMainThread:@selector(_notifyDelegateOfExtractedLength:) withObject:[NSNumber numberWithLong:len] waitUntilDone:NO];
	}
	pclose(cmdFP);
	
	[self performSelectorOnMainThread:@selector(_notifyDelegateOfSuccess) withObject:nil waitUntilDone:NO];
	goto finally;
	
reportError:
	[self performSelectorOnMainThread:@selector(_notifyDelegateOfFailure) withObject:nil waitUntilDone:NO];
	
finally:
	if (fp)
		fclose(fp);
	[pool drain];
}

- (void)_extractTAR
{
	return [self _extractArchivePipingDataToCommand:@"tar -xC \"$DESTINATION\""];
}

- (void)_extractTGZ
{
	return [self _extractArchivePipingDataToCommand:@"tar -zxC \"$DESTINATION\""];
}

- (void)_extractTBZ
{
	return [self _extractArchivePipingDataToCommand:@"tar -jxC \"$DESTINATION\""];
}

- (void)_extractZIP
{
	return [self _extractArchivePipingDataToCommand:@"ditto -x -k - \"$DESTINATION\""];
}

+ (void)load
{
	[self _registerImplementation:self];
}

@end
