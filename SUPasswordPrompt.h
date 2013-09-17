//
//  SUPasswordPrompt.h
//  Sparkle
//
//  Created by rudy on 8/18/09.
//  Copyright 2009 Ambrosia Software, Inc.. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "Sparkle/SUWindowController.h"

@interface SUPasswordPrompt : SUWindowController 
{
	IBOutlet NSImageView *mIconView;
	IBOutlet NSTextField *mTextDescription;
	IBOutlet NSSecureTextField *mPasswordField;
	NSString *mPassword;
	NSString *mName;
	NSImage *mIcon;
}

- (id)initWithHost:(SUHost *)aHost;
- (NSInteger)run;
- (NSString *)password;

@end
