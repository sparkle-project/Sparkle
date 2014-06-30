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
static const NSTimeInterval SUParentQuitCheckInterval = .5;

@interface TerminationListener : NSObject <SUInstallerDelegate>
{
	const char		*hostpath;
	const char		*executablepath;
	pid_t			parentprocessid;
	const char		*folderpath;
	NSString		*selfPath;
    NSString        *installationPath;
	NSTimer			*watchdogTimer;
	NSTimer			*longInstallationTimer;
	SUHost			*host;
    BOOL            shouldRelaunch;
	BOOL			shouldShowUI;
}

- (void) parentHasQuit;

- (void) relaunch;
- (void) install;

- (void) showAppIconInDock:(NSTimer *)aTimer;
- (void) watchdog:(NSTimer *)aTimer;

@end

@implementation TerminationListener

- (instancetype) initWithHostPath:(const char *)inhostpath executablePath:(const char *)execpath parentProcessId:(pid_t)ppid folderPath:(const char*)infolderpath shouldRelaunch:(BOOL)relaunch shouldShowUI:(BOOL)showUI selfPath:(NSString*)inSelfPath
{
	if (!(self = [super init])) {
		return nil;
	}

	hostpath		= inhostpath;
	executablepath	= execpath;
	parentprocessid	= ppid;
	folderpath		= infolderpath;
	selfPath		= [inSelfPath retain];
    shouldRelaunch  = relaunch;
	shouldShowUI	= showUI;

	BOOL	alreadyTerminated = (getppid() == 1); // ppid is launchd (1) => parent terminated already

	if( alreadyTerminated )
		[self parentHasQuit];
	else
		watchdogTimer = [[NSTimer scheduledTimerWithTimeInterval:SUParentQuitCheckInterval target:self selector:@selector(watchdog:) userInfo:nil repeats:YES] retain];

	return self;
}


-(void)	dealloc
{
	[longInstallationTimer invalidate];
	[longInstallationTimer release];
	longInstallationTimer = nil;

	[selfPath release];
	selfPath = nil;

    [installationPath release];

	[watchdogTimer release];
	watchdogTimer = nil;

	[host release];
	host = nil;

	[super dealloc];
}


-(void)	parentHasQuit
{
	[watchdogTimer invalidate];
	longInstallationTimer = [[NSTimer scheduledTimerWithTimeInterval:SUInstallationTimeLimit
								target: self selector: @selector(showAppIconInDock:)
								userInfo:nil repeats:NO] retain];

	if( folderpath )
		[self install];
	else
		[self relaunch];
}

- (void)watchdog:(NSTimer *) __unused aTimer
{
	if (![NSRunningApplication runningApplicationWithProcessIdentifier:parentprocessid]) {
		[self parentHasQuit];
}
}

- (void)showAppIconInDock:(NSTimer *) __unused aTimer
{
	ProcessSerialNumber		psn = { 0, kCurrentProcess };
	TransformProcessType( &psn, kProcessTransformToForegroundApplication );
}


- (void) relaunch __attribute__((noreturn))
{
    if (shouldRelaunch)
    {
        NSString	*appPath = nil;
        if( !folderpath || strcmp(executablepath, hostpath) != 0 )
            appPath = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:executablepath length:strlen(executablepath)];
        else
            appPath = installationPath;
        [[NSWorkspace sharedWorkspace] openFile: appPath];
    }

    if (folderpath)
    {
        NSError *theError = nil;
        if( ![SUPlainInstaller _removeFileAtPath: [SUInstaller updateFolder] error: &theError] )
            SULog( @"Couldn't remove update folder: %@.", theError );
    }
    [[NSFileManager defaultManager] removeItemAtPath: selfPath error: NULL];

	exit(EXIT_SUCCESS);
}


- (void) install
{
	NSBundle			*theBundle = [NSBundle bundleWithPath: [[NSFileManager defaultManager] stringWithFileSystemRepresentation: hostpath length:strlen(hostpath)]];
	host = [[SUHost alloc] initWithBundle: theBundle];
    installationPath = [[host installationPath] copy];

    if (shouldShowUI) {
        SUStatusController*	statusCtl = [[SUStatusController alloc] initWithHost: host];	// We quit anyway after we've installed, so leak this for now.
        [statusCtl setButtonTitle: SULocalizedString(@"Cancel Update",@"") target: nil action: Nil isDefault: NO];
        [statusCtl beginActionWithTitle: SULocalizedString(@"Installing update...",@"")
                        maxProgressValue: 0 statusText: @""];
        [statusCtl showWindow: self];
		[statusCtl release];
    }

	[SUInstaller installFromUpdateFolder: [[NSFileManager defaultManager] stringWithFileSystemRepresentation: folderpath length: strlen(folderpath)]
					overHost: host
            installationPath: installationPath
					delegate: self synchronously: NO
					versionComparator: [SUStandardVersionComparator defaultComparator]];
}

- (void)installerFinishedForHost:(SUHost *) __unused aHost
{
	[self relaunch];
}

- (void)installerForHost:(SUHost *) __unused host failedWithError:(NSError *)error __attribute__((noreturn))
{
    if (shouldShowUI)
        NSRunAlertPanel( @"", @"%@", @"OK", @"", @"", [error localizedDescription] );
	exit(EXIT_FAILURE);
}

@end

int main (int argc, const char * argv[])
{
	if (argc < 5 || argc > 7) {
		return EXIT_FAILURE;
	}

	@autoreleasepool {
		//ProcessSerialNumber		psn = { 0, kCurrentProcess };
		//TransformProcessType( &psn, kProcessTransformToForegroundApplication );

#if 0	// Cmdline tool
		NSString*	selfPath = nil;
		if (argv[0][0] == '/') {
			selfPath = [[NSFileManager defaultManager] stringWithFileSystemRepresentation: argv[0] length: strlen(argv[0])];
		}
		else
		{
			selfPath = [[NSFileManager defaultManager] currentDirectoryPath];
			selfPath = [selfPath stringByAppendingPathComponent: [[NSFileManager defaultManager] stringWithFileSystemRepresentation: argv[0] length: strlen(argv[0])]];
		}
#else
		NSString*	selfPath = [[NSBundle mainBundle] bundlePath];
#endif

		BOOL shouldShowUI = (argc > 6) ? !!atoi(argv[6]) : YES;
		if (shouldShowUI)
		{
			[[NSApplication sharedApplication] activateIgnoringOtherApps: YES];
		}

		[NSApplication sharedApplication];
		[[[TerminationListener alloc] initWithHostPath: (argc > 1) ? argv[1] : NULL
										executablePath: (argc > 2) ? argv[2] : NULL
									   parentProcessId: (argc > 3) ? atoi(argv[3]) : 0
											folderPath: (argc > 4) ? argv[4] : NULL
										shouldRelaunch: (argc > 5) ? !!atoi(argv[5]) : YES
										  shouldShowUI: shouldShowUI
											  selfPath: selfPath] autorelease];
		[[NSApplication sharedApplication] run];

	}

	return EXIT_SUCCESS;
}
