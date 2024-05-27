//
//  SUTestApplicationDelegate.m
//  Sparkle
//
//  Created by Mayur Pawashe on 7/25/15.
//  Copyright (c) 2015 Sparkle Project. All rights reserved.
//

#import "SUTestApplicationDelegate.h"
#import "SUUpdateSettingsWindowController.h"
#import "SUTestWebServer.h"
#import "TestAppHelperProtocol.h"
#import "ed25519.h"
#import <Sparkle/Sparkle.h>
#import "SUPopUpTitlebarUserDriver.h"
#import "SUBinaryDeltaCreate.h"

@interface SUTestApplicationDelegate () <NSMenuItemValidation, SPUUpdaterDelegate>
@end

@implementation SUTestApplicationDelegate
{
    SPUUpdater *_updater;
    SUUpdateSettingsWindowController *_updateSettingsWindowController;
    SUTestWebServer *_webServer;
    NSString *_testMode;
}

- (void)applicationDidFinishLaunching:(NSNotification * __unused)notification
{
    NSBundle *mainBundle = [NSBundle mainBundle];
    
    NSString *testModeEnv = [[[NSProcessInfo processInfo] environment] objectForKey:@"TEST_MODE"];
    NSString *testMode;
    if (testModeEnv == nil) {
        testMode = @"REGULAR";
    } else {
        testMode = testModeEnv;
    }
    
    _testMode = testMode;
    
    // Check if we are already up to date
    NSString *mainBundleVersion = (NSString *)[mainBundle objectForInfoDictionaryKey:(__bridge NSString *)kCFBundleVersionKey];
    
    if (([mainBundleVersion hasPrefix:@"2."] && [testMode isEqualToString:@"REGULAR"]) || (([mainBundleVersion isEqualToString:@"2.1"] || [mainBundleVersion isEqualToString:@"2.2"]) && [testMode isEqualToString:@"DELTA"]) || ([mainBundleVersion isEqualToString:@"2.2"] && [testMode isEqualToString:@"AUTOMATIC"])) {
        NSAlert *alreadyUpdatedAlert = [[NSAlert alloc] init];
        alreadyUpdatedAlert.messageText = @"Update succeeded!";
        alreadyUpdatedAlert.informativeText = @"This is the updated version of Sparkle Test App.\n\nDelete and rebuild the app to test updates again.";
        [alreadyUpdatedAlert runModal];
        
        [[NSApplication sharedApplication] terminate:nil];
    }
    
#if SPARKLE_BUILD_UI_BITS
    // Detect as early as possible if the shift key is held down
    BOOL shiftKeyHeldDown = ([NSEvent modifierFlags] & NSEventModifierFlagShift) != 0;
#endif

    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    // Locate user's cache directory
    NSError *cacheError = nil;
    NSURL *cacheDirectoryURL = [[NSFileManager defaultManager] URLForDirectory:NSCachesDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:&cacheError];
    
    if (cacheDirectoryURL == nil) {
        NSLog(@"Failed to locate cache directory with error: %@", cacheError);
        abort();
    }
    
    NSString *bundleIdentifier = mainBundle.bundleIdentifier;
    assert(bundleIdentifier != nil);
    
    // Create a directory that'll be used for our web server listing
    NSURL *serverDirectoryURL = [[cacheDirectoryURL URLByAppendingPathComponent:bundleIdentifier] URLByAppendingPathComponent:@"ServerData"];
    if ([serverDirectoryURL checkResourceIsReachableAndReturnError:nil]) {
        NSError *removeServerDirectoryError = nil;
        
        if (![fileManager removeItemAtURL:serverDirectoryURL error:&removeServerDirectoryError]) {
            abort();
        }
    }
    
    NSError *createDirectoryError = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtURL:serverDirectoryURL withIntermediateDirectories:YES attributes:nil error:&createDirectoryError]) {
        NSLog(@"Failed creating directory at %@ with error %@", serverDirectoryURL.path, createDirectoryError);
        abort();
    }
    
    NSURL *bundleURL = mainBundle.bundleURL;
    assert(bundleURL != nil);
    
    // Copy main bundle into server directory
    NSString *bundleURLLastComponent = bundleURL.lastPathComponent;
    assert(bundleURLLastComponent != nil);
    
    NSURL *destinationBundleURL = [serverDirectoryURL URLByAppendingPathComponent:bundleURLLastComponent];
    NSError *copyBundleError = nil;
    if (![fileManager copyItemAtURL:bundleURL toURL:destinationBundleURL error:&copyBundleError]) {
        NSLog(@"Failed to copy main bundle into server directory with error %@", copyBundleError);
        abort();
    }
    
    // Update bundle's version keys to latest version
    NSURL *infoURL = [[destinationBundleURL URLByAppendingPathComponent:@"Contents"] URLByAppendingPathComponent:@"Info.plist"];
    
    BOOL infoFileExists = [infoURL checkResourceIsReachableAndReturnError:nil];
    assert(infoFileExists);
    
    NSString *finalUpdatedVersion;
    if ([testMode isEqualToString:@"REGULAR"]) {
        finalUpdatedVersion = @"2.0";
    } else if ([testMode isEqualToString:@"DELTA"]) {
        finalUpdatedVersion = @"2.1";
    } else if ([testMode isEqualToString:@"AUTOMATIC"]) {
        finalUpdatedVersion = @"2.2";
    } else {
        assert(false);
    }
    
    NSMutableDictionary *infoDictionary = [[NSMutableDictionary alloc] initWithContentsOfURL:infoURL];
    [infoDictionary setObject:finalUpdatedVersion forKey:(__bridge NSString *)kCFBundleVersionKey];
    [infoDictionary setObject:finalUpdatedVersion forKey:@"CFBundleShortVersionString"];
    
    BOOL wroteInfoFile = [infoDictionary writeToURL:infoURL atomically:NO];
    assert(wroteInfoFile);
    
    // Overwrite and add new data
    {
        NSURL *screenshotURL = [[[[destinationBundleURL URLByAppendingPathComponent:@"Contents"] URLByAppendingPathComponent:@"Resources"] URLByAppendingPathComponent:@"screenshot"] URLByAppendingPathExtension:@"png"];
        assert([screenshotURL checkResourceIsReachableAndReturnError:NULL]);
        
        NSMutableData *screenshotData = [NSMutableData dataWithContentsOfURL:screenshotURL];
        
        uint32_t garbage = 1337;
        [screenshotData appendBytes:&garbage length:sizeof(garbage)];
        
        BOOL wroteData = [screenshotData writeToURL:screenshotURL atomically:NO];
        assert(wroteData);
        
        NSURL *newDataURL = [[screenshotURL URLByDeletingLastPathComponent] URLByAppendingPathComponent:@"new_file"];
        assert(newDataURL != nil);
        
        BOOL wroteNewData = [[NSData dataWithBytes:&garbage length:sizeof(garbage)] writeToURL:newDataURL atomically:NO];
        assert(wroteNewData);
    }
    
    [self signApplicationIfRequiredAtPath:destinationBundleURL.path completion:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            // Change current working directory so web server knows where to list files
            NSString *serverDirectoryPath = serverDirectoryURL.path;
            assert(serverDirectoryPath != nil);
            
            NSString * const appcastName = @"sparkletestcast";
            NSString * const appcastExtension = @"xml";
            
            // Copy our appcast over to the server directory
            NSURL *appcastDestinationURL = [[serverDirectoryURL URLByAppendingPathComponent:appcastName] URLByAppendingPathExtension:appcastExtension];
            NSError *copyAppcastError = nil;
            NSURL *appcastURL = [mainBundle URLForResource:appcastName withExtension:appcastExtension];
            assert(appcastURL != nil);
            if (![fileManager copyItemAtURL:appcastURL toURL:appcastDestinationURL error:&copyAppcastError]) {
                NSLog(@"Failed to copy appcast into cache directory with error %@", copyAppcastError);
                abort();
            }
            
            // Update the appcast with the file size and signature of the update archive
            // We could be using some sort of XML parser instead of doing string substitutions, but for now, this is easier
            NSError *appcastError = nil;
            NSMutableString *appcastContents = [[NSMutableString alloc] initWithContentsOfURL:appcastDestinationURL encoding:NSUTF8StringEncoding error:&appcastError];
            if (appcastContents == nil) {
                NSLog(@"Failed to load appcast contents with error %@", appcastError);
                abort();
            }
            
            // Don't ever do this at home, kids (seriously)
            // (that is, including the private key inside of your application)
            const unsigned char self_sign_demo_only_insecure_hack[64] = {200, 238, 135, 84, 10, 189, 3, 193, 61, 208, 203, 30, 133, 47, 12, 22, 19, 52, 252, 99, 110, 205, 209, 94, 215, 144, 201, 70, 27, 162, 163, 108, 0, 164, 68, 184, 226, 93, 121, 199, 172, 17, 26, 64, 89, 68, 232, 41, 2, 26, 245, 175, 158, 165, 42, 55, 5, 97, 8, 243, 251, 164, 93, 9};
            // in normal app this goes to Info.plist
            const unsigned char public_key[32] = {121, 17, 79, 45, 155, 141, 51, 169, 188, 110, 91, 102, 182, 147, 215, 225, 252, 202, 110, 231, 200, 215, 62, 171, 40, 145, 237, 128, 130, 44, 150, 89};
            unsigned char signature[64];
            
            if ([testMode isEqualToString:@"DELTA"]) {
                NSError *deltaCreationError = nil;
                NSURL *patchURL = [serverDirectoryURL URLByAppendingPathComponent:@"patch.delta"];
                if (!createBinaryDelta(bundleURL.path, destinationBundleURL.path, patchURL.path, SUBinaryDeltaMajorVersionDefault, SPUDeltaCompressionModeDefault, 0, NO, &deltaCreationError)) {
                    NSLog(@"Failed to create binary delta patch: %@", deltaCreationError);
                    abort();
                }
                
                NSData *archive = [NSData dataWithContentsOfURL:patchURL];
                assert(archive != nil);
                
                ed25519_sign(signature, archive.bytes, archive.length, public_key, self_sign_demo_only_insecure_hack);
                
                NSString *signatureString = [[NSData dataWithBytes:signature length:64] base64EncodedStringWithOptions:0];
                
                // Obtain the file attributes to get the file size of our update later
                NSError *fileAttributesError = nil;
                NSString *archiveURLPath = patchURL.path;
                assert(archiveURLPath != nil);
                NSDictionary *archiveFileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:archiveURLPath error:&fileAttributesError];
                if (archiveFileAttributes == nil) {
                    NSLog(@"Failed to retrieve file attributes from delta archive with error %@", fileAttributesError);
                    abort();
                }
                
                NSUInteger numberOfLengthReplacements = [appcastContents replaceOccurrencesOfString:@"$INSERT_DELTA_ARCHIVE_LENGTH" withString:[NSString stringWithFormat:@"%llu", archiveFileAttributes.fileSize] options:NSLiteralSearch range:NSMakeRange(0, appcastContents.length)];
                assert(numberOfLengthReplacements == 1);
                
                NSUInteger numberOfSignatureReplacements = [appcastContents replaceOccurrencesOfString:@"$INSERT_DELTA_EDDSA_SIGNATURE" withString:signatureString options:NSLiteralSearch range:NSMakeRange(0, appcastContents.length)];
                assert(numberOfSignatureReplacements == 1);
                
                NSUInteger numberOfFromVersionReplacements = [appcastContents replaceOccurrencesOfString:@"$INSERT_DELTA_FROM_VERSION" withString:mainBundleVersion options:NSLiteralSearch range:NSMakeRange(0, appcastContents.length)];
                assert(numberOfFromVersionReplacements == 1);
                
                NSError *writeAppcastError = nil;
                if (![appcastContents writeToURL:appcastDestinationURL atomically:NO encoding:NSUTF8StringEncoding error:&writeAppcastError]) {
                    NSLog(@"Failed to write updated appcast with error %@", writeAppcastError);
                    abort();
                }
            } else {
                // Create the archive for our update
                NSString *zipName = @"Sparkle_Test_App.zip";
                NSTask *dittoTask = [[NSTask alloc] init];
                dittoTask.launchPath = @"/usr/bin/ditto";
                dittoTask.arguments = @[@"-c", @"-k", @"--sequesterRsrc", @"--keepParent", (NSString *)destinationBundleURL.lastPathComponent, zipName];
                dittoTask.currentDirectoryPath = serverDirectoryPath;
                [dittoTask launch];
                [dittoTask waitUntilExit];
                
                assert(dittoTask.terminationStatus == 0);
                
                NSURL *archiveURL = [serverDirectoryURL URLByAppendingPathComponent:zipName];
                NSData *archive = [NSData dataWithContentsOfURL:archiveURL];
                assert(archive != nil);

                ed25519_sign(signature, archive.bytes, archive.length, public_key, self_sign_demo_only_insecure_hack);

                NSString *signatureString = [[NSData dataWithBytes:signature length:64] base64EncodedStringWithOptions:0];
                
                // Obtain the file attributes to get the file size of our update later
                NSError *fileAttributesError = nil;
                NSString *archiveURLPath = archiveURL.path;
                assert(archiveURLPath != nil);
                NSDictionary *archiveFileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:archiveURLPath error:&fileAttributesError];
                if (archiveFileAttributes == nil) {
                    NSLog(@"Failed to retrieve file attributes from archive with error %@", fileAttributesError);
                    abort();
                }
                
                NSUInteger numberOfLengthReplacements = [appcastContents replaceOccurrencesOfString:@"$INSERT_ARCHIVE_LENGTH" withString:[NSString stringWithFormat:@"%llu", archiveFileAttributes.fileSize] options:NSLiteralSearch range:NSMakeRange(0, appcastContents.length)];
                assert(numberOfLengthReplacements == 2);
                
                NSUInteger numberOfSignatureReplacements = [appcastContents replaceOccurrencesOfString:@"$INSERT_EDDSA_SIGNATURE" withString:signatureString options:NSLiteralSearch range:NSMakeRange(0, appcastContents.length)];
                assert(numberOfSignatureReplacements == 2);
                
                NSError *writeAppcastError = nil;
                if (![appcastContents writeToURL:appcastDestinationURL atomically:NO encoding:NSUTF8StringEncoding error:&writeAppcastError]) {
                    NSLog(@"Failed to write updated appcast with error %@", writeAppcastError);
                    abort();
                }
            }
            
            [fileManager removeItemAtURL:destinationBundleURL error:NULL];
            
            // Finally start the server
            SUTestWebServer *webServer = [[SUTestWebServer alloc] initWithPort:1337 workingDirectory:serverDirectoryPath];
            if (!webServer) {
                NSLog(@"Failed to create the web server");
                abort();
            }
            self->_webServer = webServer;
            
            // Set up updater and the updater settings window
            {
                self->_updateSettingsWindowController = [[SUUpdateSettingsWindowController alloc] init];
                
                NSWindow *settingsWindow = self->_updateSettingsWindowController.window;
                
                NSBundle *hostBundle = [NSBundle mainBundle];
                NSBundle *applicationBundle = hostBundle;
                
                id<SPUUserDriver> userDriver;
#if SPARKLE_BUILD_UI_BITS
                if (shiftKeyHeldDown) {
                    userDriver = [[SUPopUpTitlebarUserDriver alloc] initWithWindow:settingsWindow];
                } else {
                    userDriver = [[SPUStandardUserDriver alloc] initWithHostBundle:hostBundle delegate:nil];
                }
#else
                userDriver = [[SUPopUpTitlebarUserDriver alloc] initWithWindow:settingsWindow];
#endif
                
                SPUUpdater *updater = [[SPUUpdater alloc] initWithHostBundle:hostBundle applicationBundle:applicationBundle userDriver:userDriver delegate:self];
                
                self->_updater = updater;
                self->_updateSettingsWindowController.updater = updater;
                
                NSError *updaterError = nil;
                if (![updater startUpdater:&updaterError]) {
                    NSLog(@"Failed to start updater with error: %@", updaterError);
                    
                    NSAlert *alert = [[NSAlert alloc] init];
                    alert.messageText = @"Updater Error";
                    alert.informativeText = @"The Updater failed to start. For detailed error information, check the Console.app log.";
                    [alert addButtonWithTitle:@"OK"];
                    [alert runModal];
                }
                
                [self->_updateSettingsWindowController showWindow:nil];
            }
        });
    }];
}

- (NSSet<NSString *> *)allowedChannelsForUpdater:(SPUUpdater *)updater
{
    if ([_testMode isEqualToString:@"DELTA"]) {
        return [NSSet setWithObject:@"delta"];
    } else if ([_testMode isEqualToString:@"AUTOMATIC"]) {
        return [NSSet setWithObject:@"automatic"];
    } else {
        return [NSSet set];
    }
}

- (void)signApplicationIfRequiredAtPath:(NSString *)applicationPath completion:(void (^)(void))completionBlock SPU_OBJC_DIRECT
{
    // This is unfortunately necessary for testing sandboxing
    NSXPCConnection *codeSignConnection = [[NSXPCConnection alloc] initWithServiceName:@"org.sparkle-project.TestAppHelper"];
    codeSignConnection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(TestAppHelperProtocol)];
    [codeSignConnection resume];
    
    [(id<TestAppHelperProtocol>)codeSignConnection.remoteObjectProxy codeSignApplicationAtPath:applicationPath reply:^(BOOL success) {
        assert(success);
        [codeSignConnection invalidate];
        
        completionBlock();
    }];
}

- (void)applicationWillTerminate:(NSNotification * __unused)notification
{
    [_webServer close];
}

- (IBAction)checkForUpdates:(id __unused)sender
{
    [_updater checkForUpdates];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
    if (menuItem.action == @selector(checkForUpdates:)) {
        return _updater.canCheckForUpdates;
    }
    return YES;
}

@end
