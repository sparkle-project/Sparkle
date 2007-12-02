//
//  NTSynchronousTask.h
//  CocoatechCore
//
//  Created by Steve Gehrman on 9/29/05.
//  Copyright 2005 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface NTSynchronousTask : NSObject
{
    NSTask *mv_task;
    NSPipe *mv_outputPipe;
    NSPipe *mv_inputPipe;
	
	NSData* mv_output;
	BOOL mv_done;
	int mv_result;
}

// pass nil for directory if not needed
// returns the result
+ (NSData*)task:(NSString*)toolPath directory:(NSString*)currentDirectory withArgs:(NSArray*)args input:(NSData*)input;

@end
