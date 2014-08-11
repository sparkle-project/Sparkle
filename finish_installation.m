
#import <AppKit/AppKit.h>
#import "SUInstaller.h"
#import "SUHost.h"
#import "SUStandardVersionComparator.h"
#import "SUStatusController.h"
#import "SUPlainInstallerInternals.h"
#import "SULog.h"

#include <unistd.h>

#define	LONG_INSTALLATION_TIME			5				// If the Installation takes longer than this time the Application Icon is shown in the Dock so that the user has some feedback.
#define	CHECK_FOR_PARENT_TO_QUIT_TIME	.5				// Time this app uses to recheck if the parent has already died.
										
@interface TerminationListener : NSObject
{
	const char *hostpath;
	const char *executablepath;
	pid_t parentprocessid;
	const char *folderpath;
	NSString *selfPath;
    NSString *installationPath;
	NSTimer *watchdogTimer;
	NSTimer *longInstallationTimer;
	SUHost *host;
    SUFinishUpdateTask finishTasks;
}

- (void)parentHasQuit;

- (void)relaunch;
- (void)install;

- (SUHost *)host;

- (void)showAppIconInDock:(NSTimer *)aTimer;
- (void)watchdog:(NSTimer *)aTimer;

@end

@implementation TerminationListener

- (id)initWithHostPath:(const char *)inhostpath
        executablePath:(const char *)execpath
       parentProcessId:(pid_t)ppid
            folderPath:(const char*)infolderpath
       finishTasksMask:(SUFinishUpdateTask)tasks
              selfPath:(NSString*)inSelfPath
{
    self = [super init];
	if (nil == self)
		return nil;
    
	hostpath = inhostpath;
	executablepath = execpath;
	parentprocessid	= ppid;
	folderpath = infolderpath;
    finishTasks = tasks;
	selfPath = [inSelfPath retain];
	
    if (NULL != hostpath)
    {
        NSString *bundlePath = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:hostpath length:strlen(hostpath)];
        NSBundle *theBundle = [NSBundle bundleWithPath:bundlePath];
        host = [[SUHost alloc] initWithBundle:theBundle];
    }

	BOOL alreadyTerminated = (getppid() == 1); // ppid is launchd (1) => parent terminated already
	
	if (alreadyTerminated || 0 == (finishTasks & SUFinishUpdateWithRelaunch))
    {
		[self parentHasQuit];
    }
	else
    {
		watchdogTimer = [[NSTimer scheduledTimerWithTimeInterval:CHECK_FOR_PARENT_TO_QUIT_TIME target:self selector:@selector(watchdog:) userInfo:nil repeats:YES] retain];
    }

	return self;
}


- (void)dealloc
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


- (void)parentHasQuit
{
	[watchdogTimer invalidate];
	longInstallationTimer = [[NSTimer scheduledTimerWithTimeInterval:LONG_INSTALLATION_TIME
                                                              target:self
                                                            selector:@selector(showAppIconInDock:)
                                                            userInfo:nil
                                                             repeats:NO]
                             retain];

	if (folderpath && (SUFinishUpdateWithInstall & finishTasks))
		[self install];
	else
		[self relaunch];
}

- (void)watchdog:(NSTimer *)aTimer
{
	ProcessSerialNumber psn;
	if (GetProcessForPID(parentprocessid, &psn) == procNotFound)
		[self parentHasQuit];
}

- (void)showAppIconInDock:(NSTimer *)aTimer;
{
	ProcessSerialNumber psn = { 0, kCurrentProcess };
	TransformProcessType(&psn, kProcessTransformToForegroundApplication);
}

- (void)relaunch
{
    if (SUFinishUpdateWithRelaunch & finishTasks)
    {
        NSString *appPath = nil;
        if (!folderpath || strcmp(executablepath, hostpath) != 0)
            appPath = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:executablepath length:strlen(executablepath)];
        else
            appPath = installationPath;
        [[NSWorkspace sharedWorkspace] openFile:appPath];
    }

    if (folderpath)
    {
        NSError *theError = nil;
        if (![SUPlainInstaller _removeFileAtPath:[SUInstaller updateFolder] error:&theError])
            SULog(@"Couldn't remove update folder: %@.", theError);
    }
    [[NSFileManager defaultManager] removeItemAtPath:selfPath error:NULL];

	exit(EXIT_SUCCESS);
}


- (void)install
{
    if (0 == (SUFinishUpdateWithInstall & finishTasks))
        return;
    
    installationPath = [[host installationPath] copy];
	
    // Perhaps a poor assumption but: if we're not relaunching, we assume we shouldn't be showing any UI either. Because non-relaunching installations are kicked off without any user interaction, we shouldn't be interrupting them.
    if (SUFinishUpdateWithRelaunch & finishTasks)
    {
        SUStatusController *statusCtl = [[SUStatusController alloc] initWithHost:host];	// We quit anyway after we've installed, so leak this for now.
        [statusCtl setButtonTitle:SULocalizedString(@"Cancel Update", @"") target:nil action:nil isDefault:NO];
        [statusCtl beginActionWithTitle:SULocalizedString(@"Installing update...", @"")
                       maxProgressValue:0
                             statusText:@""];
        [statusCtl showWindow:self];
    }
	
    NSString *updateFolder =[[NSFileManager defaultManager] stringWithFileSystemRepresentation:folderpath length:strlen(folderpath)];
	[SUInstaller installFromUpdateFolder:updateFolder
                                overHost:host
                        installationPath:installationPath
                                delegate:self
                           synchronously:NO
                       versionComparator:[SUStandardVersionComparator defaultComparator]];
}

- (void)installerFinishedForHost:(SUHost *)aHost
{
	[self relaunch];
}

- (void)installerForHost:(SUHost *)host failedWithError:(NSError *)error
{
    // Perhaps a poor assumption but: if we're not relaunching, we assume we shouldn't be showing any UI either. Because non-relaunching installations are kicked off without any user interaction, we shouldn't be interrupting them.
    if (SUFinishUpdateWithRelaunch & finishTasks)
        NSRunAlertPanel(@"", @"%@", @"OK", @"", @"", [error localizedDescription]);
	exit(EXIT_FAILURE);
}

- (SUHost *)host
{
	return host;
}

@end

int main(int argc, const char * argv[])
{
	if (argc < 6)
		return EXIT_FAILURE;
	
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	//ProcessSerialNumber		psn = { 0, kCurrentProcess };
	//TransformProcessType( &psn, kProcessTransformToForegroundApplication );
	[[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
		
	#if 0	// Cmdline tool
	NSString*	selfPath = nil;
	if( argv[0][0] == '/' )
		selfPath = [[NSFileManager defaultManager] stringWithFileSystemRepresentation: argv[0] length: strlen(argv[0])];
	else
	{
		selfPath = [[NSFileManager defaultManager] currentDirectoryPath];
		selfPath = [selfPath stringByAppendingPathComponent: [[NSFileManager defaultManager] stringWithFileSystemRepresentation: argv[0] length: strlen(argv[0])]];
	}
	#else
	NSString *selfPath = [[NSBundle mainBundle] bundlePath];
	#endif

	[NSApplication sharedApplication];
	
	NSConnection *connection = [[[NSConnection alloc] init] autorelease];
	TerminationListener *listener = [[[TerminationListener alloc] initWithHostPath:argv[1]
                                                                    executablePath:argv[2]
                                                                   parentProcessId:atoi(argv[3])
                                                                        folderPath:argv[4]
                                                                   finishTasksMask:atoi(argv[5])
                                                                          selfPath:selfPath]
                                     autorelease];
	
	[connection setRootObject:listener];
	if (![connection registerName:[NSString stringWithFormat:@"Sparkle %@", [[[listener host] bundle] bundleIdentifier]]])
	{
		NSLog(@"%s server: could not register server.  Is one already running?\n", argv[0]);
	}
	
	[[NSApplication sharedApplication] run];
	
	[pool drain];
	
	return EXIT_SUCCESS;
}
