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
    [self.appInstaller start];
}

@end

int main(int __unused argc, const char __unused *argv[])
{
    @autoreleasepool
    {
        NSArray *args = [[NSProcessInfo processInfo] arguments];
        if (args.count != 2) {
            return EXIT_FAILURE;
        }
        
        NSString *hostBundleIdentifier = args[1];
        
        AppInstaller *appInstaller = [[AppInstaller alloc] initWithHostBundleIdentifier:hostBundleIdentifier];
        
        AppDelegate *delegate = [[AppDelegate alloc] initWithAppInstaller:appInstaller];
        
        NSApplication *application = [NSApplication sharedApplication];
        [application setDelegate:delegate];
        
        [application run];
    }

    return EXIT_SUCCESS;
}
