#import <AppKit/AppKit.h>
#import "SUInstaller.h"
#import "SUHost.h"
#import "SUStandardVersionComparator.h"
#import "SUStatusController.h"
#import "SUPlainInstallerInternals.h"
#import "SULog.h"

#include <unistd.h>

/*!
 * If the Installation takes longer than this time the Application Icon is shown in the Dock so that the user has some feedback.
 */
static const NSTimeInterval SUInstallationTimeLimit = 5;

/*!
 * Time this app uses to recheck if the parent has already died.
 */
static const NSTimeInterval SUParentQuitCheckInterval = .25;

@interface TerminationListener : NSObject

@property (copy) NSString *hostpath;
@property (copy) NSString *executablepath;
@property (assign) pid_t parentprocessid;
@property (copy) NSString *folderpath;

@property (copy) NSString *selfPath;
@property (copy) NSString *installationPath;
@property (strong) NSTimer *watchdogTimer;
@property (strong) NSTimer *longInstallationTimer;
@property (strong) SUHost *host;
@property (assign) BOOL shouldRelaunch;
@property (assign) BOOL shouldShowUI;
@property (strong) SUStatusController *statusController;

- (void)parentHasQuit;

- (void)relaunch;
- (void)install;

- (void)showAppIconInDock:(NSTimer *)aTimer;
- (void)watchdog:(NSTimer *)aTimer;

@end

@implementation TerminationListener

@synthesize hostpath;
@synthesize executablepath;
@synthesize parentprocessid;
@synthesize folderpath;

@synthesize selfPath;
@synthesize installationPath;
@synthesize watchdogTimer;
@synthesize longInstallationTimer;
@synthesize host;
@synthesize shouldRelaunch;
@synthesize shouldShowUI;
@synthesize statusController;

- (instancetype)initWithHostPath:(NSString *)inhostpath executablePath:(NSString *)execpath parentProcessId:(pid_t)ppid folderPath:(NSString *)infolderpath shouldRelaunch:(BOOL)relaunch shouldShowUI:(BOOL)showUI selfPath:(NSString *)inSelfPath
{
    if (!(self = [super init])) {
        return nil;
    }

    self.hostpath = inhostpath;
    self.executablepath = execpath;
    self.parentprocessid = ppid;
    self.folderpath = infolderpath;
    self.selfPath = inSelfPath;
    self.shouldRelaunch = relaunch;
    self.shouldShowUI = showUI;

    BOOL alreadyTerminated = (getppid() == 1); // ppid is launchd (1) => parent terminated already

    if (alreadyTerminated)
        [self parentHasQuit];
    else
        self.watchdogTimer = [NSTimer scheduledTimerWithTimeInterval:SUParentQuitCheckInterval target:self selector:@selector(watchdog:) userInfo:nil repeats:YES];

    return self;
}


- (void)dealloc
{
    [self.longInstallationTimer invalidate];
    [self.statusController close];
}


- (void)parentHasQuit
{
    [self.watchdogTimer invalidate];
    self.longInstallationTimer = [NSTimer scheduledTimerWithTimeInterval:SUInstallationTimeLimit
								target: self selector: @selector(showAppIconInDock:)
								userInfo:nil repeats:NO];

    if (self.folderpath)
        [self install];
    else
        [self relaunch];
}

- (void)watchdog:(NSTimer *)__unused aTimer
{
    if (![NSRunningApplication runningApplicationWithProcessIdentifier:self.parentprocessid]) {
        [self parentHasQuit];
    }
}

- (void)showAppIconInDock:(NSTimer *)__unused aTimer
{
    ProcessSerialNumber psn = { 0, kCurrentProcess };
    TransformProcessType(&psn, kProcessTransformToForegroundApplication);
}


- (void)relaunch __attribute__((noreturn))
{
    if (self.shouldRelaunch)
    {
        NSString *appPath = nil;
        if (!self.folderpath || ![self.executablepath isEqualToString:self.hostpath])
            appPath = self.executablepath;
        else
            appPath = self.installationPath;
        [[NSWorkspace sharedWorkspace] openFile:appPath];
    }

    if (self.folderpath)
    {
        NSError *theError = nil;
        if (![SUPlainInstaller _removeFileAtPath:[SUInstaller updateFolder] error:&theError])
            SULog(@"Couldn't remove update folder: %@.", theError);
    }
    [[NSFileManager defaultManager] removeItemAtPath:self.selfPath error:NULL];

    exit(EXIT_SUCCESS);
}


- (void)install
{
    NSBundle *theBundle = [NSBundle bundleWithPath:self.hostpath];
    self.host = [[SUHost alloc] initWithBundle:theBundle];
    self.installationPath = [[self.host installationPath] copy];

    if (self.shouldShowUI) {
        SUStatusController *statusCtl = [[SUStatusController alloc] initWithHost:self.host]; // We quit anyway after we've installed, so leak this for now.
        [statusCtl setButtonTitle:SULocalizedString(@"Cancel Update", @"") target:nil action:Nil isDefault:NO];
        [statusCtl beginActionWithTitle:SULocalizedString(@"Installing update...", @"")
                        maxProgressValue: 0 statusText: @""];
        [statusCtl showWindow:self];

        [self.statusController close]; // If there's an existing status controller, close it before we release our strong reference to it.
        self.statusController = statusCtl; // Keep a strong reference to the status controller, or else it might get prematurely deallocated.
    }

    [SUInstaller installFromUpdateFolder:self.folderpath
                                overHost:self.host
                        installationPath:self.installationPath
                       versionComparator:[SUStandardVersionComparator defaultComparator]
                       completionHandler:^(NSError *error) {
                           if (error) {
                               if (self.shouldShowUI) {
                                   NSAlert *alert = [[NSAlert alloc] init];
                                   alert.messageText = @"";
                                   alert.informativeText = [NSString stringWithFormat:@"%@", [error localizedDescription]];
                                   [alert runModal];
                               }
                               exit(EXIT_FAILURE);
                           } else {
                               [self relaunch];
                           }
                       }];
}

@end

int main(int __unused argc, const char __unused *argv[])
{
    @autoreleasepool
    {
        NSArray *args = [[NSProcessInfo processInfo] arguments];
        if (args.count < 5 || args.count > 7) {
            return EXIT_FAILURE;
        }

        BOOL shouldShowUI = (args.count > 6) ? [args[6] boolValue] : YES;
        if (shouldShowUI) {
            [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
        }

        [NSApplication sharedApplication];
        TerminationListener *termListen = [[TerminationListener alloc] initWithHostPath:args[1]
                                                                         executablePath:args[2]
                                                                        parentProcessId:[args[3] intValue]
                                                                             folderPath:args[4]
                                                                         shouldRelaunch:(args.count > 5) ? [args[5] boolValue] : YES
                                                                           shouldShowUI:shouldShowUI
                                                                               selfPath:[[NSBundle mainBundle] bundlePath]];

        [[NSApplication sharedApplication] run];
        // Ensure termListen is not deallocated by ARC before caling -[NSApplication run]
        [termListen class];
    }

    return EXIT_SUCCESS;
}
