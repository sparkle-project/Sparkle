#import <Cocoa/Cocoa.h>
#import "SULog.h"
#import "AppInstaller.h"

@interface AppDelegate : NSObject <NSApplicationDelegate>

@property (nonatomic, readonly) AppInstaller *appInstaller;

@end

@implementation AppDelegate

@synthesize appInstaller = _appInstaller;

- (instancetype)initWithAppInstaller:(AppInstaller *)appInstaller
{
    self = [super init];
    if (self != nil) {
        _appInstaller = appInstaller;
    }
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification __unused *)notification
{
    [self.appInstaller extractAndInstallUpdate];
}

@end

int main(int __unused argc, const char __unused *argv[])
{
    @autoreleasepool
    {
        NSArray *args = [[NSProcessInfo processInfo] arguments];
        if (args.count != 7) {
            return EXIT_FAILURE;
        }
        
        NSString *relaunchPath = args[1];
        NSString *hostBundlePath = args[2];
        NSString *updateDirectoryPath = args[3];
        NSString *downloadPath = args[4];
        NSString *dsaSignature = args[5];
        BOOL shouldRelaunchTool = [args[6] boolValue];
        
        if (shouldRelaunchTool) {
            NSURL *mainBundleURL = [[NSBundle mainBundle] bundleURL];
            
            if (mainBundleURL == nil) {
                SULog(@"Error: No bundle path located found for main bundle!");
                return EXIT_FAILURE;
            }
            
            NSMutableArray *launchArguments = [args mutableCopy];
            [launchArguments removeObjectAtIndex:0]; // argv[0] is not important
            launchArguments[launchArguments.count - 1] = @"0"; // we don't want to relaunch the tool this time
            
            // We want to launch our tool through LaunchServices, not through a NSTask instance
            // This has a few advantages: one being that we don't inherit the privileges of the parent owner.
            // Another is if we try to spawn a task, it may be prematurely terminated if the parent is like a XPC service,
            // which is what the shouldRelaunchTool flag exists to prevent. Thus, a caller may specify to relaunch the tool again and
            // wait until we exit. When we exit the first time, the caller will be notified, and we can launch a second instance through LS.
            // The caller may not have AppKit available which is why it may not launch through LS itself.
            NSError *launchError = nil;
            NSRunningApplication *newRunningApplication = [[NSWorkspace sharedWorkspace] launchApplicationAtURL:mainBundleURL options:(NSWorkspaceLaunchOptions)(NSWorkspaceLaunchDefault | NSWorkspaceLaunchNewInstance) configuration:@{NSWorkspaceLaunchConfigurationArguments : [launchArguments copy]} error:&launchError];
            
            if (newRunningApplication == nil) {
                SULog(@"Failed to create second instance of tool with error: %@", launchError);
                return EXIT_FAILURE;
            }
            
            return EXIT_SUCCESS;
        }
        
        AppInstaller *appInstaller =
        [[AppInstaller alloc]
         initWithHostPath:hostBundlePath
         relaunchPath:relaunchPath
         updateFolderPath:updateDirectoryPath
         downloadPath:downloadPath
         dsaSignature:dsaSignature];
        
        AppDelegate *delegate = [[AppDelegate alloc] initWithAppInstaller:appInstaller];
        
        NSApplication *application = [NSApplication sharedApplication];
        [application setDelegate:delegate];
        [application run];
    }

    return EXIT_SUCCESS;
}
