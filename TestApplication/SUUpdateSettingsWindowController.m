//
//  SUUpdateSettingsWindowController.m
//  Sparkle
//
//  Created by Mayur Pawashe on 7/25/15.
//  Copyright (c) 2015 Sparkle Project. All rights reserved.
//

#import "SUUpdateSettingsWindowController.h"

@interface SUUpdateSettingsWindowController ()

@property (nonatomic) IBOutlet SUUpdater *updater;

@end

@implementation SUUpdateSettingsWindowController

@synthesize updater = _updater;

- (void)windowDidLoad
{
    self.updater.delegate = self;
}

- (NSString *)windowNibName
{
    return NSStringFromClass([self class]);
}

- (IBAction)checkForUpdates:(id __unused)sender
{
    [self.updater checkForUpdates:nil];
}

- (BOOL)handlePermissionForUpdater:(SUUpdater *)updater host:(SUHost *)host systemProfile:(NSArray *)systemProfile reply:(void (^)(SUUpdatePermissionPromptResult *))reply
{
    NSLog(@"App is asking us for permission!! Replying YES");
    reply([SUUpdatePermissionPromptResult updatePermissionPromptResultWithChoice:SUAutomaticallyCheck shouldSendProfile:NO]);
    
    return YES;
}

- (BOOL)startUserInitiatedUpdateCheckWithUpdater:(SUUpdater *)updater host:(SUHost *)host cancelUpdateCheck:(void (^)(void))cancelUpdateCheck
{
    NSLog(@"USER INITIATED THE UPDATE!");
    
    return YES;
}

- (BOOL)stopUserInitiatedUpdateCheckWithUpdater:(SUUpdater *)updater host:(SUHost *)host
{
    NSLog(@"User Initiated update is finished!!");
    
    return YES;
}

- (BOOL)handlePresentingError:(NSError *)error toUserWithUpdater:(SUUpdater *)updater
{
    NSLog(@"Ran into bad error with updater :(. Error: %@", error);
    
    return YES;
}

- (BOOL)handlePresentingNoUpdateFoundWithUpdater:(SUUpdater *)updater
{
    NSLog(@"No new update is available right now you know");
    
    return YES;
}

- (BOOL)handleUpdateFoundWithUpdater:(SUUpdater *)updater host:(SUHost *)host appcastItem:(SUAppcastItem *)appcastItem versionDisplayer:(id<SUVersionDisplay>)versionDisplayer reply:(void (^)(SUUpdateAlertChoice))reply
{
    NSLog(@"Update was found! GOING TO SAY YES %@", appcastItem);
    
    reply(SUInstallUpdateChoice);
    
	return YES;
}

- (BOOL)handlePresentingDownloadInitiatedWithUpdater:(SUUpdater *)updater host:(SUHost *)host cancelDownload:(void (^)(void))cancelDownload
{
    NSLog(@"Download yerself an update!");
    
	return YES;
}

- (BOOL)handleOpeningInfoURLWithUpdater:(SUUpdater *)updater appcastItem:(SUAppcastItem *)appcastItem
{
    NSLog(@"User wanted to open info url %@ .. whatever", appcastItem.infoURL);
    
	return YES;
}

- (BOOL)handleDownloadDidReceiveResponse:(NSURLResponse *)response withUpdater:(SUUpdater *)updater
{
    NSLog(@"Download has started 'cos it recieved a response!");
    
	return YES;
}

- (BOOL)handleDownloadDidReceiveDataOfLength:(NSUInteger)length withUpdater:(SUUpdater *)updater
{
    NSLog(@"Download received data of length %lu !", length);
    
	return YES;
}

- (BOOL)handleStartExtractingUpdateWithUpdater:(SUUpdater *)updater
{
    NSLog(@"Extracting the update!!");
    
	return YES;
}

- (BOOL)handleExtractionDidReceiveProgress:(double)progress withUpdater:(SUUpdater *)updater
{
    NSLog(@"Extracting the update with progress: %f!!", progress);
    
	return YES;
}

- (BOOL)handleExtractionDidFinishExtractingWithUpdater:(SUUpdater *)updater installUpdate:(void (^)(void))installUpdate
{
    NSLog(@"Extraction finished!! Installing update yes!");
    
    installUpdate();
    
	return YES;
}

- (BOOL)handleInstallingUpdateWithUpdater:(SUUpdater *)updater
{
    NSLog(@"The update is going to install any second now!");
    
	return YES;
}

@end
