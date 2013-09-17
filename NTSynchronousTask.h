//
//  NTSynchronousTask.h
//  CocoatechCore
//
//  Created by Steve Gehrman on 9/29/05.
//  Copyright 2005 Steve Gehrman. All rights reserved.
//

#ifndef NTSYNCHRONOUSTASK_H
#define NTSYNCHRONOUSTASK_H

@interface NTSynchronousTask : NSObject
{
@private
    NSTask *mv_task;
    NSPipe *mv_outputPipe;
    NSPipe *mv_inputPipe;
	
	NSData* mv_output;
	BOOL mv_done;
	int mv_result;
}

// pass nil for directory if not needed
// returns the result
+(int)	task:(NSString*)toolPath directory:(NSString*)currentDirectory withArgs:(NSArray*)args input:(NSData*)input output: (NSData**)outData;

+(NSData*)task:(NSString*)toolPath directory:(NSString*)currentDirectory withArgs:(NSArray*)args input:(NSData*)input;

- (void)run:(NSString*)toolPath directory:(NSString*)currentDirectory withArgs:(NSArray*)args input:(NSData*)input;
- (int)result;
- (NSData *)output;

@end

#endif
