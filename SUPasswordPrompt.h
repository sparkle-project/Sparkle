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
- (void)awakeFromNib;
- (void)setName:(NSString*)name;
- (NSString*)name;
- (void)setIcon:(NSImage*)icon;
- (NSImage*)icon;
- (NSString *)password;
- (void)setPassword:(NSString*)password;
- (NSInteger)run;
- (IBAction)accept:(id)sender;
- (IBAction)cancel:(id)sender;
- (void)replaceTitle:(NSString*)name;

@end
