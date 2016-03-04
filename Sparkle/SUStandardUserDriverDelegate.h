//
//  SUStandardUserDriverDelegate.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/3/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol SUStandardUserDriverUIDelegate, SUStandardUserDriverRemoteDelegate;

/*!
 A protocol for Sparkle's standard user driver's delegate
 
 If you are interested in UI interactions, check out SUStandardUserDriverUIDelegate
 If you are interested in XPC or remote process communications for efficiency and reliability, check out SUStandardUserDriverRemoteDelegate
 */
@protocol SUStandardUserDriverDelegate <SUStandardUserDriverUIDelegate, SUStandardUserDriverRemoteDelegate>
@end
