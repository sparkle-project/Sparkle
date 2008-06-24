//
//  NTSynchronousTask.m
//  CocoatechCore
//
//  Created by Steve Gehrman on 9/29/05.
//  Copyright 2005 Steve Gehrman. All rights reserved.
//

#import "Sparkle.h"
#import "NTSynchronousTask.h"

@interface NTSynchronousTask (Private)
- (void)run:(NSString*)toolPath directory:(NSString*)currentDirectory withArgs:(NSArray*)args input:(NSData*)input;

- (NSTask *)task;
- (void)setTask:(NSTask *)theTask;

- (NSPipe *)outputPipe;
- (void)setOutputPipe:(NSPipe *)theOutputPipe;

- (NSPipe *)inputPipe;
- (void)setInputPipe:(NSPipe *)theInputPipe;

- (NSData *)output;
- (void)setOutput:(NSData *)theOutput;

- (BOOL)done;
- (void)setDone:(BOOL)flag;

- (int)result;
- (void)setResult:(int)theResult;
@end

@implementation NTSynchronousTask

- (id)init;
{
    self = [super init];
	if (self)
	{
		[self setTask:[[[NSTask alloc] init] autorelease]];
		[self setOutputPipe:[[[NSPipe alloc] init] autorelease]];
		[self setInputPipe:[[[NSPipe alloc] init] autorelease]];
		
		[[self task] setStandardInput:[self inputPipe]];
		[[self task] setStandardOutput:[self outputPipe]];
	}
	
    return self;
}

//---------------------------------------------------------- 
// dealloc
//---------------------------------------------------------- 
- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];

    [self setTask:nil];
    [self setOutputPipe:nil];
    [self setInputPipe:nil];
	[self setOutput:nil];

    [super dealloc];
}

+ (NSData*)task:(NSString*)toolPath directory:(NSString*)currentDirectory withArgs:(NSArray*)args input:(NSData*)input;
{
	// we need this wacky pool here, otherwise we run out of pipes, the pipes are internally autoreleased
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSData* result=nil;
	
	NS_DURING
	{
		NTSynchronousTask* task = [[NTSynchronousTask alloc] init];
		
		[task run:toolPath directory:currentDirectory withArgs:args input:input];
		
		if ([task result] == 0)
			result = [[task output] retain];
				
		[task release];
	}	
	NS_HANDLER;
	NS_ENDHANDLER;
	
	[pool drain];
	
	// retained above
	[result autorelease];
	
    return result;
}

@end

@implementation NTSynchronousTask (Private)

- (void)run:(NSString*)toolPath directory:(NSString*)currentDirectory withArgs:(NSArray*)args input:(NSData*)input;
{
	BOOL success = NO;
	
	if (currentDirectory)
		[[self task] setCurrentDirectoryPath: currentDirectory];
	
	[[self task] setLaunchPath:toolPath];
	[[self task] setArguments:args];
				
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(taskOutputAvailable:)
												 name:NSFileHandleReadToEndOfFileCompletionNotification
											   object:[[self outputPipe] fileHandleForReading]];
		
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(taskDidTerminate:)
												 name:NSTaskDidTerminateNotification
											   object:[self task]];	
	
	[[[self outputPipe] fileHandleForReading] readToEndOfFileInBackgroundAndNotifyForModes:[NSArray arrayWithObjects:NSDefaultRunLoopMode, NSModalPanelRunLoopMode, NSEventTrackingRunLoopMode, nil]];
	
	NS_DURING
		[[self task] launch];
		success = YES;
	NS_HANDLER
		;
	NS_ENDHANDLER
	
	if (success)
	{
		if (input)
		{
			// feed the running task our input
			[[[self inputPipe] fileHandleForWriting] writeData:input];
			[[[self inputPipe] fileHandleForWriting] closeFile];
		}
						
		// loop until we are done receiving the data
		if (![self done])
		{
			double resolution = 1;
			BOOL isRunning;
			NSDate* next;
			
			do {
				next = [NSDate dateWithTimeIntervalSinceNow:resolution]; 
				
				isRunning = [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
													 beforeDate:next];
			} while (isRunning && ![self done]);
		}
	}
}

//---------------------------------------------------------- 
//  task 
//---------------------------------------------------------- 
- (NSTask *)task
{
    return mv_task; 
}

- (void)setTask:(NSTask *)theTask
{
    if (mv_task != theTask) {
        [mv_task release];
        mv_task = [theTask retain];
    }
}

//---------------------------------------------------------- 
//  outputPipe 
//---------------------------------------------------------- 
- (NSPipe *)outputPipe
{
    return mv_outputPipe; 
}

- (void)setOutputPipe:(NSPipe *)theOutputPipe
{
    if (mv_outputPipe != theOutputPipe) {
        [mv_outputPipe release];
        mv_outputPipe = [theOutputPipe retain];
    }
}

//---------------------------------------------------------- 
//  inputPipe 
//---------------------------------------------------------- 
- (NSPipe *)inputPipe
{
    return mv_inputPipe; 
}

- (void)setInputPipe:(NSPipe *)theInputPipe
{
    if (mv_inputPipe != theInputPipe) {
        [mv_inputPipe release];
        mv_inputPipe = [theInputPipe retain];
    }
}

//---------------------------------------------------------- 
//  output 
//---------------------------------------------------------- 
- (NSData *)output
{
    return mv_output; 
}

- (void)setOutput:(NSData *)theOutput
{
    if (mv_output != theOutput) {
        [mv_output release];
        mv_output = [theOutput retain];
    }
}

//---------------------------------------------------------- 
//  done 
//---------------------------------------------------------- 
- (BOOL)done
{
    return mv_done;
}

- (void)setDone:(BOOL)flag
{
    mv_done = flag;
}

//---------------------------------------------------------- 
//  result 
//---------------------------------------------------------- 
- (int)result
{
    return mv_result;
}

- (void)setResult:(int)theResult
{
    mv_result = theResult;
}

@end

@implementation NTSynchronousTask (Notifications)

- (void)taskOutputAvailable:(NSNotification*)note
{
	[self setOutput:[[note userInfo] objectForKey:NSFileHandleNotificationDataItem]];
	
	[self setDone:YES];
}

- (void)taskDidTerminate:(NSNotification*)note
{
    [self setResult:[[self task] terminationStatus]];
}

@end


