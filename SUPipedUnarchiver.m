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

+ (SEL)_selectorConformingToTypeOfURL:(NSURL *)URL
{
	static NSDictionary *typeSelectorDictionary;
	// HACK: The UTI detector is dumb (not my fault!) and sees .tar.gz files as plain .gz files. If we see something of type .bz2 or .gz, we'll assume it's really a .tar.bz2 or .tar.gz.
	if (!typeSelectorDictionary)
		typeSelectorDictionary = [[NSDictionary dictionaryWithObjectsAndKeys:@"_extractZIP", @"com.pkware.zip-archive",
								   @"_extractTGZ", @"org.gnu.gnu-zip-tar-archive", @"_extractTGZ", @"org.gnu.gnu-zip-archive",
								   @"_extractTBZ", @"org.bzip.bzip2-tar-archive", @"_extractTBZ", @"org.bzip.bzip2-archive", @"_extractTBZ", @"public.archive.bzip2",
								   @"_extractTAR", @"public.tar-archive", nil] retain];

	NSEnumerator *typeEnumerator = [typeSelectorDictionary keyEnumerator];
	id currentType;
	while ((currentType = [typeEnumerator nextObject]))
	{
		if ([URL conformsToType:currentType])
			return NSSelectorFromString([typeSelectorDictionary objectForKey:currentType]);
	}
	return NULL;
}

- (void)start
{
	[NSThread detachNewThreadSelector:[[self class] _selectorConformingToTypeOfURL:archiveURL] toTarget:self withObject:nil];
}

+ (BOOL)_canUnarchiveURL:(NSURL *)URL
{
	return ([self _selectorConformingToTypeOfURL:URL] != nil);
}

// This method abstracts the types that use a command line tool piping data from stdin.
- (void)_extractArchivePipingDataToCommand:(NSString *)command
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSString *archivePath = [archiveURL path];
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
