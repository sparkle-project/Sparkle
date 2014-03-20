//
//  SUPlainInstallerInternalsTest.m
//  Sparkle
//
//  Created by Daniel Jalkut on 3/20/14.
//
//

#import <SenTestingKit/SenTestingKit.h>
#import "SUPlainInstallerInternals.h"

@interface SUPlainInstallerInternalsTest : SenTestCase
{
	NSString* temporaryFolder;
}

@end

@implementation SUPlainInstallerInternalsTest

- (void)setUp
{
	temporaryFolder = nil;
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown
{
 	// If we created a temporary folder for our testing purposes, delete it now
	if (temporaryFolder != nil)
	{
		(void) [[NSFileManager defaultManager] removeItemAtPath:temporaryFolder error:nil];

		[temporaryFolder release];
		temporaryFolder = nil;
	}

    [super tearDown];
}

- (void) dealloc
{
	[temporaryFolder release];
	[super dealloc];
}

- (BOOL) createFolderAtPath:(NSString*)thePath
{
	return [[NSFileManager defaultManager] createDirectoryAtPath:thePath withIntermediateDirectories:YES attributes:nil error:nil];
}

- (NSString*) pathToTemporaryFolder
{
	if (temporaryFolder == nil)
	{
		// Guard against possibility for NSTemporaryDirectory to return nil
		NSString* tempFolderParent = NSTemporaryDirectory();
		if (tempFolderParent == nil) tempFolderParent = @"/tmp/";
		
		NSString* testFolderName = [NSString stringWithFormat:@"%@-%@", NSStringFromClass([self class]), [[NSUUID UUID] UUIDString]];
		NSString* testFileStoragePath = [tempFolderParent stringByAppendingPathComponent:testFolderName];

		[self createFolderAtPath:testFileStoragePath];
		temporaryFolder = [testFileStoragePath retain];

		STAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:testFileStoragePath], @"Creating a temporary scratch folder for our tests should work.");
	}
	
	return temporaryFolder;
}

- (BOOL) fileAtPath:(NSString*)path1 identicalToFileAtPath:(NSString*)path2
{
	NSData* data1 = [NSData dataWithContentsOfFile:path1];
	NSData* data2 = [NSData dataWithContentsOfFile:path2];
	return [data1 isEqual:data2];
}

- (NSDictionary*) unreadableAttributes
{
	return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithUnsignedInteger:0300U], NSFilePosixPermissions, nil];
}

- (NSDictionary*) unwritableAttributes
{
	return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithUnsignedInteger:0500U], NSFilePosixPermissions, nil];
}

- (void) testInstallerFileCopying
{
	NSString* testContainerPath = [self pathToTemporaryFolder];
	NSString* writableTargetFolderPath = [testContainerPath stringByAppendingPathComponent:@"writable"];
	[self createFolderAtPath:writableTargetFolderPath];

	// Set up basic source and destination files
	NSString* sourceFile1 = [[self pathToTemporaryFolder] stringByAppendingPathComponent:@"sourceFile1"];
	[[NSFileManager defaultManager] copyItemAtPath:@"/bin/ls" toPath:sourceFile1 error:nil];
	NSString* sourceFile2 = [[self pathToTemporaryFolder] stringByAppendingPathComponent:@"sourceFile2"];
	[[NSFileManager defaultManager] copyItemAtPath:@"/bin/rm" toPath:sourceFile2 error:nil];
	NSString* targetFilePath = [writableTargetFolderPath stringByAppendingPathComponent:@"sourceCopy"];
	NSString* bogusSourceFilePath = @"/bingle/ls";
	NSString* bogusTargetFilePath = [testContainerPath stringByAppendingPathComponent:@"alksjdf"];

	NSError* errorDuringCopy = nil;
	BOOL copySuccess = YES;

	// Case: Bogus source and a bogus destination should fail
	copySuccess = [SUPlainInstaller copyPathWithAuthentication:bogusSourceFilePath overPath:bogusTargetFilePath error:&errorDuringCopy];
	STAssertFalse(copySuccess, @"Copying with bogus source and destination should fail.");

	// Case: Simple copy where the target does not already exist
	copySuccess = [SUPlainInstaller copyPathWithAuthentication:sourceFile1 overPath:targetFilePath error:&errorDuringCopy];
	STAssertTrue(copySuccess, @"Copying with no authentication required should succeed.");
	STAssertTrue([self fileAtPath:sourceFile1 identicalToFileAtPath:targetFilePath], @"After copying the source and dst should appear identical");

	// Case: Simple copy where the target *does* already exist ... just copy over it again with something else
	copySuccess = [SUPlainInstaller copyPathWithAuthentication:sourceFile2 overPath:targetFilePath error:&errorDuringCopy];
	STAssertTrue(copySuccess, @"Re-Copying with no authentication required should succeed.");
	STAssertFalse([self fileAtPath:sourceFile1 identicalToFileAtPath:targetFilePath], @"After copying the old source and dst should NOT appear identical");
	STAssertTrue([self fileAtPath:sourceFile2 identicalToFileAtPath:targetFilePath], @"After copying the NEW source and dst should appear identical");

	// Case: Exercise failure code path where the target folder is writable but the copy fails for some reason.
	// An easy scenario that exercises this is to have the source file be a valid path, but one that will fail during
	// copy becuase of permissions errors.
	// First restore the original case where the /bin/ls is copied to the target file path
	copySuccess = [SUPlainInstaller copyPathWithAuthentication:sourceFile1 overPath:targetFilePath error:&errorDuringCopy];
	STAssertTrue(copySuccess, @"Copying with no authentication required should succeed.");
	
	NSString* unreadableSourceFile = [testContainerPath stringByAppendingPathComponent:@"unreadable"];
	[[NSFileManager defaultManager] createFileAtPath:unreadableSourceFile contents:[NSData dataWithBytes:"Hello" length:5] attributes:[self unreadableAttributes]];
	copySuccess = [SUPlainInstaller copyPathWithAuthentication:unreadableSourceFile overPath:targetFilePath error:&errorDuringCopy];
	STAssertFalse(copySuccess, @"Copy should fail when the source file is unreadable");

	// This confirms the copying back of a file from the tmpPath location
	STAssertTrue([self fileAtPath:sourceFile1 identicalToFileAtPath:targetFilePath], @"After failing to copy a bogus source over it, original source and dst should appear identical");

	// Confirm the error is roughly meaningful
	BOOL looksLikeCopyError = ([[errorDuringCopy localizedDescription] rangeOfString:@"Couldn't move"].location != NSNotFound);
	STAssertTrue(looksLikeCopyError, @"After failing to copy over we should get a reasonable error.");

	// This test case is intended to cover the failure mode in which a file exists at the destination but cannot
	// be moved because the move fails for some reason. I have yet to establish a suitable test case for this because
	// the obvious technique is to make the parent folder unwritable, but doing so causes other code paths to be
	// reached that take an "authentication-based" copying approach. How do we ensure that the target file is unmovable
	// without making the target file's folder writable? Maybe some ACL-based approach?
#if 0
	NSString* unwritableTargetFolder = [testContainerPath stringByAppendingPathComponent:@"unwritable"];
	[[NSFileManager defaultManager] createDirectoryAtPath:unwritableTargetFolder withIntermediateDirectories:YES attributes:nil error:nil];
	NSString* unmovableTargetFile = [unwritableTargetFolder stringByAppendingPathComponent:@"unmovableTarget"];
	[[NSFileManager defaultManager] createFileAtPath:unmovableTargetFile contents:[NSData dataWithBytes:"Hello" length:5] attributes:nil];
	[[NSFileManager defaultManager] setAttributes:[self unwritableAttributes] ofItemAtPath:unwritableTargetFolder error:nil];
	copySuccess = [SUPlainInstaller copyPathWithAuthentication:sourceFile1 overPath:unmovableTargetFile temporaryName:nil error:&errorDuringCopy];
	STAssertFalse(copySuccess, @"Copy should fail when the target file is unreadable and can't be moved to e.g. trash");
	looksLikeCopyError = ([[errorDuringCopy localizedDescription] rangeOfString:@"Couldn't move"].location != NSNotFound);
	STAssertTrue(looksLikeCopyError, @"After failing to copy over we should get a reasonable error.");
#endif
}

// Unwritten tests: these should probably be added but because they have to do with authentication
// prompts we will have to also build in some mechanism for stubbing out the authentication process.
// For example if SUPlainInstallerInternals was configurable with some ability to provide authentication
// details through code, then the authorizations could be performed by fetching credentials from a keychain
// and feeding them in, rather than requiring the user to babysit the tests and enter passwords for each auth.

// Case: Authentication required because the target exists and is writable, but the parent is not writable

// Case: Authentication required because the target exists but is not writeable

// Case: Confirming a previous bug in Sparkle, target does not exist and the parent IS writable, but the
// parent's parent is not writable. In this case we should NOT require authentication.

@end
