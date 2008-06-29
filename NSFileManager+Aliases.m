//
//  NSFileManager+Aliases.m
//  Sparkle
//
//  Created by Andy Matuschak on 2/4/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "NSFileManager+Aliases.h"


@implementation NSFileManager (SUAliases)

- (BOOL)isAliasFolderAtPath:(NSString *)path
{
	FSRef fileRef;
	OSStatus err = noErr;
	Boolean aliasFileFlag, folderFlag;
	NSURL *fileURL = [NSURL fileURLWithPath:path];
	
	if (FALSE == CFURLGetFSRef((CFURLRef)fileURL, &fileRef))
		err = coreFoundationUnknownErr;
	
	if (noErr == err)
		err = FSIsAliasFile(&fileRef, &aliasFileFlag, &folderFlag);
	
	if (noErr == err)
		return (BOOL)(aliasFileFlag && folderFlag);
	else
		return NO;	
}

@end
