//
//  NTSynchronousTask.m
//  CocoatechCore
//
//  Created by Steve Gehrman on 9/29/05.
//  Copyright 2005 Steve Gehrman. All rights reserved.
//

#import "SUUpdater.h"

#import "SUAppcast.h"
#import "SUAppcastItem.h"
#import "SUVersionComparisonProtocol.h"
#import "NTSynchronousTask.h"

@interface NTSynchronousTask ()
@property (retain) NSTask *task;
@property (retain) NSPipe *outputPipe;
@property (retain) NSPipe *inputPipe;
@property (readwrite, retain) NSData *output;
@property (getter = isDone) BOOL done;
@property (readwrite) int result;
@end

@implementation NTSynchronousTask
@synthesize output = mv_output;
@synthesize result = mv_result;
@synthesize task = mv_task;
@synthesize outputPipe = mv_outputPipe;
@synthesize inputPipe = mv_inputPipe;
@synthesize done = mv_done;

- (void)taskOutputAvailable:(NSNotification*)note
{
	self.output = [[note userInfo] objectForKey:NSFileHandleNotificationDataItem];
	
	self.done = YES;
}

- (void)taskDidTerminate:(NSNotification*)note
{
    self.result = [self.task terminationStatus];
}

- (id)init;
{
    self = [super init];
	if (self)
	{
		self.task = [[[NSTask alloc] init] autorelease];
		self.outputPipe = [[[NSPipe alloc] init] autorelease];
		self.inputPipe = [[[NSPipe alloc] init] autorelease];
		
		self.task.standardInput = self.inputPipe;
		self.task.standardOutput = self.outputPipe;
		self.task.standardError = self.outputPipe;
	}
	
    return self;
}

//---------------------------------------------------------- 
// dealloc
//---------------------------------------------------------- 
- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];

    self.task = nil;
    self.outputPipe = nil;
    self.inputPipe = nil;
	self.output = nil;

    [super dealloc];
}

- (void)run:(NSString*)toolPath directory:(NSString*)currentDirectory withArgs:(NSArray*)args input:(NSData*)input
{
	BOOL success = NO;
	
	if (currentDirectory)
		self.task.currentDirectoryPath = currentDirectory;
	
	self.task.launchPath = toolPath;
	self.task.arguments = args;
				
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(taskOutputAvailable:)
												 name:NSFileHandleReadToEndOfFileCompletionNotification
											   object:[[self outputPipe] fileHandleForReading]];
		
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(taskDidTerminate:)
												 name:NSTaskDidTerminateNotification
											   object:[self task]];	
	
	[[[self outputPipe] fileHandleForReading] readToEndOfFileInBackgroundAndNotifyForModes:[NSArray arrayWithObjects:NSDefaultRunLoopMode, NSModalPanelRunLoopMode, NSEventTrackingRunLoopMode, nil]];
	
	@try
	{
		[self.task launch];
		success = YES;
	}
	@catch (NSException *localException) { }
	
	if (success)
	{
		if (input)
		{
			// feed the running task our input
			[[self.inputPipe fileHandleForWriting] writeData:input];
			[[self.inputPipe fileHandleForWriting] closeFile];
		}
						
		// loop until we are done receiving the data
		if (!self.done)
		{
			double resolution = 1;
			BOOL isRunning;
			NSDate* next;
			
			do {
				next = [NSDate dateWithTimeIntervalSinceNow:resolution]; 
				
				isRunning = [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
													 beforeDate:next];
			} while (isRunning && !self.done);
		}
	}
}

+ (NSData*)task:(NSString*)toolPath directory:(NSString*)currentDirectory withArgs:(NSArray*)args input:(NSData*)input
{
	// we need this wacky pool here, otherwise we run out of pipes, the pipes are internally autoreleased
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSData* result = nil;
	
	@try
	{
		NTSynchronousTask* task = [[NTSynchronousTask alloc] init];
		
		[task run:toolPath directory:currentDirectory withArgs:args input:input];
		
		if ([task result] == 0)
			result = [[task output] retain];
				
		[task release];
	}	
	@catch (NSException *localException) { }
	
	[pool drain];
	
	// retained above
	[result autorelease];
	
    return result;
}


+(int)	task:(NSString*)toolPath directory:(NSString*)currentDirectory withArgs:(NSArray*)args input:(NSData*)input output: (NSData**)outData
{
	// we need this wacky pool here, otherwise we run out of pipes, the pipes are internally autoreleased
	NSAutoreleasePool *	pool = [[NSAutoreleasePool alloc] init];
	int					taskResult = 0;
	if( outData )
		*outData = nil;
	
	@try {
		NTSynchronousTask* task = [[NTSynchronousTask alloc] init];
		
		[task run:toolPath directory:currentDirectory withArgs:args input:input];
		
		taskResult = [task result];
		if( outData )
			*outData = [[task output] retain];
				
		[task release];
	} @catch (NSException *localException) {
		taskResult = errCppGeneral;
	}
	
	[pool drain];
	
	// retained above
	if( outData )
		[*outData autorelease];
	
    return taskResult;
}

@end
