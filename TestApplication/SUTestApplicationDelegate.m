//
//  SUTestApplicationDelegate.m
//  Sparkle
//
//  Created by Mayur Pawashe on 7/25/15.
//  Copyright (c) 2015 Sparkle Project. All rights reserved.
//

#import "SUTestApplicationDelegate.h"
#import "SUUpdateSettingsWindowController.h"
#import "SUFileManager.h"
#import "SUTestWebServer.h"
#import "TestAppHelperProtocol.h"

@interface SUTestApplicationDelegate ()

@property (nonatomic) NSWindowController *updateSettingsWindowController;
@property (nonatomic) SUTestWebServer *webServer;

@end

@implementation SUTestApplicationDelegate

@synthesize updateSettingsWindowController = _updateSettingsWindowController;
@synthesize webServer = _webServer;

static NSString * const UPDATED_VERSION = @"2.0";

- (void)applicationDidFinishLaunching:(NSNotification * __unused)notification
{
    NSBundle *mainBundle = [NSBundle mainBundle];
    
    // Check if we are already up to date
    if ([[mainBundle objectForInfoDictionaryKey:(__bridge NSString *)kCFBundleVersionKey] isEqualToString:UPDATED_VERSION]) {
        NSAlert *alreadyUpdatedAlert = [[NSAlert alloc] init];
        alreadyUpdatedAlert.messageText = @"Update succeeded!";
        alreadyUpdatedAlert.informativeText = @"This is the updated version of Sparkle Test App.\n\nDelete and rebuild the app to test updates again.";
        [alreadyUpdatedAlert runModal];
        
        [[NSApplication sharedApplication] terminate:nil];
    }
    
    // Detect as early as possible if the shift key is held down
    BOOL shiftKeyHeldDown = ([NSEvent modifierFlags] & NSShiftKeyMask) != 0;
    
    // Apple's file manager may not work well over the network (on macOS 10.11.4 as of writing this), but at the same time
    // I don't want to have to export SUFileManager in release mode. The test app is primarily
    // aimed to be used in debug mode, so I think this is a good compromise
#ifdef DEBUG
    SUFileManager *fileManager = [[SUFileManager alloc] init];
#else
    NSFileManager *fileManager = [NSFileManager defaultManager];
#endif
    
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
    
    NSMutableDictionary *infoDictionary = [[NSMutableDictionary alloc] initWithContentsOfURL:infoURL];
    [infoDictionary setObject:UPDATED_VERSION forKey:(__bridge NSString *)kCFBundleVersionKey];
    [infoDictionary setObject:UPDATED_VERSION forKey:@"CFBundleShortVersionString"];
    
    BOOL wroteInfoFile = [infoDictionary writeToURL:infoURL atomically:NO];
    assert(wroteInfoFile);
    
    [self signApplicationIfRequiredAtPath:destinationBundleURL.path completion:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            // Change current working directory so web server knows where to list files
            NSString *serverDirectoryPath = serverDirectoryURL.path;
            assert(serverDirectoryPath != nil);
            
            // Create the archive for our update
            NSString *zipName = @"Sparkle_Test_App.zip";
            NSTask *dittoTask = [[NSTask alloc] init];
            dittoTask.launchPath = @"/usr/bin/ditto";
            dittoTask.arguments = @[@"-c", @"-k", @"--sequesterRsrc", @"--keepParent", destinationBundleURL.lastPathComponent, zipName];
            dittoTask.currentDirectoryPath = serverDirectoryPath;
            [dittoTask launch];
            [dittoTask waitUntilExit];
            
            assert(dittoTask.terminationStatus == 0);
            
            [fileManager removeItemAtURL:destinationBundleURL error:NULL];
            
            // Don't ever do this at home, kids (seriously)
            // (that is, including the private key inside of your application)
            NSString *privateKeyPath = [mainBundle pathForResource:@"test_app_only_dsa_priv_dont_ever_do_this_for_real" ofType:@"pem"];
            assert(privateKeyPath != nil);
            
            // Sign our update
            NSTask *signUpdateTask = [[NSTask alloc] init];
            NSString *signUpdatePath = [mainBundle pathForResource:@"sign_update" ofType:@""];
            assert(signUpdatePath != nil);
            signUpdateTask.launchPath = signUpdatePath;
            
            NSURL *archiveURL = [serverDirectoryURL URLByAppendingPathComponent:zipName];
            signUpdateTask.arguments = @[archiveURL.path, privateKeyPath];
            
            NSPipe *outputPipe = [NSPipe pipe];
            signUpdateTask.standardOutput = outputPipe;
            
            [signUpdateTask launch];
            [signUpdateTask waitUntilExit];
            
            assert(signUpdateTask.terminationStatus == 0);
            
            NSData *signatureData = [outputPipe.fileHandleForReading readDataToEndOfFile];
            NSString *signature = [[[NSString alloc] initWithData:signatureData encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            
            assert(signature != nil);
            
            // Obtain the file attributes to get the file size of our update later
            NSError *fileAttributesError = nil;
            NSString *archiveURLPath = archiveURL.path;
            assert(archiveURLPath != nil);
            NSDictionary *archiveFileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:archiveURLPath error:&fileAttributesError];
            if (archiveFileAttributes == nil) {
                NSLog(@"Failed to retrieve file attributes from archive with error %@", fileAttributesError);
                abort();
            }
            
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
            
            NSUInteger numberOfLengthReplacements = [appcastContents replaceOccurrencesOfString:@"$INSERT_ARCHIVE_LENGTH" withString:[NSString stringWithFormat:@"%llu", archiveFileAttributes.fileSize] options:NSLiteralSearch range:NSMakeRange(0, appcastContents.length)];
            assert(numberOfLengthReplacements == 1);
            
            NSUInteger numberOfSignatureReplacements = [appcastContents replaceOccurrencesOfString:@"$INSERT_DSA_SIGNATURE" withString:signature options:NSLiteralSearch range:NSMakeRange(0, appcastContents.length)];
            assert(numberOfSignatureReplacements == 1);
            
            NSError *writeAppcastError = nil;
            if (![appcastContents writeToURL:appcastDestinationURL atomically:NO encoding:NSUTF8StringEncoding error:&writeAppcastError]) {
                NSLog(@"Failed to write updated appcast with error %@", writeAppcastError);
                abort();
            }
            
            // Finally start the server
            SUTestWebServer *webServer = [[SUTestWebServer alloc] initWithPort:1337 workingDirectory:serverDirectoryPath];
            if (!webServer) {
                NSLog(@"Failed to create the web server");
                abort();
            }
            self.webServer = webServer;
            
            // Show the Settings window
            self.updateSettingsWindowController = [[SUUpdateSettingsWindowController alloc] initWithCustomUserDriver:shiftKeyHeldDown];
            
            [self.updateSettingsWindowController showWindow:nil];
        });
    }];
}

- (void)signApplicationIfRequiredAtPath:(NSString *)applicationPath completion:(void (^)(void))completionBlock
{
#ifdef DEBUG
    // This is unfortunately necessary for testing sandboxing
    NSXPCConnection *codeSignConnection = [[NSXPCConnection alloc] initWithServiceName:@"org.sparkle-project.TestAppHelper"];
    codeSignConnection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(TestAppHelperProtocol)];
    [codeSignConnection resume];
    
    [codeSignConnection.remoteObjectProxy codeSignApplicationAtPath:applicationPath reply:^(BOOL success) {
        assert(success);
        [codeSignConnection invalidate];
        
        completionBlock();
    }];
#else
    (void)(applicationPath); // ignore unused warning
    completionBlock();
#endif
}

- (void)applicationWillTerminate:(NSNotification * __unused)notification
{
    [self.webServer close];
}

@end
