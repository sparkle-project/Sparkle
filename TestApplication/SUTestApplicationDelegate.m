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
#import "ed25519.h" // Run `git submodule update --init` if you get an error here

@interface SUTestApplicationDelegate ()

@property (nonatomic) SUUpdateSettingsWindowController *updateSettingsWindowController;
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
    if ([(NSString *)[mainBundle objectForInfoDictionaryKey:(__bridge NSString *)kCFBundleVersionKey] isEqualToString:UPDATED_VERSION]) {
        NSAlert *alreadyUpdatedAlert = [[NSAlert alloc] init];
        alreadyUpdatedAlert.messageText = @"Update succeeded!";
        alreadyUpdatedAlert.informativeText = @"This is the updated version of Sparkle Test App.\n\nDelete and rebuild the app to test updates again.";
        [alreadyUpdatedAlert runModal];
        
        [[NSApplication sharedApplication] terminate:nil];
    }
    
    SUFileManager *fileManager = [SUFileManager defaultManager];
    
    // Locate user's cache directory
    NSError *cacheError = nil;
    NSURL *cacheDirectoryURL = [[NSFileManager defaultManager] URLForDirectory:NSCachesDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:&cacheError];
    
    if (cacheDirectoryURL == nil) {
        NSLog(@"Failed to locate cache directory with error: %@", cacheError);
        assert(NO);
    }
    
    NSString *bundleIdentifier = mainBundle.bundleIdentifier;
    assert(bundleIdentifier != nil);
    
    // Create a directory that'll be used for our web server listing
    NSURL *serverDirectoryURL = [[cacheDirectoryURL URLByAppendingPathComponent:bundleIdentifier] URLByAppendingPathComponent:@"ServerData"];
    if ([serverDirectoryURL checkResourceIsReachableAndReturnError:nil]) {
        NSError *removeServerDirectoryError = nil;
        
        if (![fileManager removeItemAtURL:serverDirectoryURL error:&removeServerDirectoryError]) {
            assert(NO);
        }
    }
    
    NSError *createDirectoryError = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtURL:serverDirectoryURL withIntermediateDirectories:YES attributes:nil error:&createDirectoryError]) {
        NSLog(@"Failed creating directory at %@ with error %@", serverDirectoryURL.path, createDirectoryError);
        assert(NO);
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
        assert(NO);
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
    
    // Change current working directory so web server knows where to list files
    NSString *serverDirectoryPath = serverDirectoryURL.path;
    assert(serverDirectoryPath != nil);
    
    // Create the archive for our update
    NSString *zipName = @"Sparkle_Test_App.zip";
    NSTask *dittoTask = [[NSTask alloc] init];
    dittoTask.launchPath = @"/usr/bin/ditto";
    NSString *lastPathComponent = destinationBundleURL.lastPathComponent;
    assert(lastPathComponent);
    dittoTask.arguments = @[@"-c", @"-k", @"--sequesterRsrc", @"--keepParent", lastPathComponent, zipName];
    dittoTask.currentDirectoryPath = serverDirectoryPath;
    [dittoTask launch];
    [dittoTask waitUntilExit];
    
    assert(dittoTask.terminationStatus == 0);
    
    [fileManager removeItemAtURL:destinationBundleURL error:NULL];
    
    // Don't ever do this at home, kids (seriously)
    // (that is, including the private key inside of your application)
    const unsigned char self_sign_demo_only_insecure_hack[64] = {200, 238, 135, 84, 10, 189, 3, 193, 61, 208, 203, 30, 133, 47, 12, 22, 19, 52, 252, 99, 110, 205, 209, 94, 215, 144, 201, 70, 27, 162, 163, 108, 0, 164, 68, 184, 226, 93, 121, 199, 172, 17, 26, 64, 89, 68, 232, 41, 2, 26, 245, 175, 158, 165, 42, 55, 5, 97, 8, 243, 251, 164, 93, 9};
    // in normal app this goes to Info.plist
    const unsigned char public_key[32] = {121, 17, 79, 45, 155, 141, 51, 169, 188, 110, 91, 102, 182, 147, 215, 225, 252, 202, 110, 231, 200, 215, 62, 171, 40, 145, 237, 128, 130, 44, 150, 89};
    unsigned char signature[64];
    
    NSURL *archiveURL = [serverDirectoryURL URLByAppendingPathComponent:zipName];
    NSData *archive = [NSData dataWithContentsOfURL:archiveURL];
    assert(archive != nil);
    
    ed25519_sign(signature, archive.bytes, archive.length, public_key, self_sign_demo_only_insecure_hack);
    
    NSString *signatureString = [[NSData dataWithBytes:signature length:64] base64Encoding];
    
    // Obtain the file attributes to get the file size of our update later
    NSError *fileAttributesError = nil;
    NSString *archivePath = archiveURL.path;
    assert(archivePath != nil);
    NSDictionary *archiveFileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:archivePath error:&fileAttributesError];
    if (archiveFileAttributes == nil) {
        NSLog(@"Failed to retrieve file attributes from archive with error %@", fileAttributesError);
        assert(NO);
    }
    
    NSString * const appcastName = @"sparkletestcast";
    NSString * const appcastExtension = @"xml";
    
    // Copy our appcast over to the server directory
    NSURL *appcastDestinationURL = [[serverDirectoryURL URLByAppendingPathComponent:appcastName] URLByAppendingPathExtension:appcastExtension];
    NSURL *appcastPath = [mainBundle URLForResource:appcastName withExtension:appcastExtension];
    assert(appcastPath);
    NSError *copyAppcastError = nil;
    if (![fileManager copyItemAtURL:appcastPath toURL:appcastDestinationURL error:&copyAppcastError]) {
        NSLog(@"Failed to copy appcast into cache directory with error %@", copyAppcastError);
        assert(NO);
    }
    
    // Update the appcast with the file size and signature of the update archive
    // We could be using some sort of XML parser instead of doing string substitutions, but for now, this is easier
    NSError *appcastError = nil;
    NSMutableString *appcastContents = [[NSMutableString alloc] initWithContentsOfURL:appcastDestinationURL encoding:NSUTF8StringEncoding error:&appcastError];
    if (appcastContents == nil) {
        NSLog(@"Failed to load appcast contents with error %@", appcastError);
        assert(NO);
    }
    
    NSUInteger numberOfLengthReplacements = [appcastContents replaceOccurrencesOfString:@"$INSERT_ARCHIVE_LENGTH" withString:[NSString stringWithFormat:@"%llu", archiveFileAttributes.fileSize] options:NSLiteralSearch range:NSMakeRange(0, appcastContents.length)];
    assert(numberOfLengthReplacements == 1);
    
    NSUInteger numberOfSignatureReplacements = [appcastContents replaceOccurrencesOfString:@"$INSERT_EDDSA_SIGNATURE" withString:signatureString options:NSLiteralSearch range:NSMakeRange(0, appcastContents.length)];
    assert(numberOfSignatureReplacements == 1);
    
    NSError *writeAppcastError = nil;
    if (![appcastContents writeToURL:appcastDestinationURL atomically:NO encoding:NSUTF8StringEncoding error:&writeAppcastError]) {
        NSLog(@"Failed to write updated appcast with error %@", writeAppcastError);
        assert(NO);
    }
    
    // Finally start the server
    SUTestWebServer *webServer = [[SUTestWebServer alloc] initWithPort:1337 workingDirectory:serverDirectoryPath];
    if (!webServer) {
        NSLog(@"Failed to create the web server");
        assert(NO);
    }
    self.webServer = webServer;
    
    // Show the Settings window
    self.updateSettingsWindowController = [[SUUpdateSettingsWindowController alloc] init];
    [self.updateSettingsWindowController showWindow:nil];
}

- (void)applicationWillTerminate:(NSNotification * __unused)notification
{
    [self.webServer close];
}

@end
