//
//  SUInstallerAgentInitiationProtocol.h
//  Sparkle
//
//  Created by Mayur Pawashe on 7/17/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol SUInstallerAgentInitiationProtocol

- (void)connectionDidInitiateWithReply:(void (^)(void))acknowledgement;

- (void)connectionWillInvalidateWithError:(NSError *)error;

@end
