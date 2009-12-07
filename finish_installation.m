
#import <AppKit/AppKit.h>
#import "SUInstaller.h"
#import "SUHost.h"
#import "SUStandardVersionComparator.h"
#import "SUStatusController.h"

#include <unistd.h>

@interface TerminationListener : NSObject
{
	const char		*executablePath;
	pid_t			parentProcessId;
	const char		*folderPath;
	NSString		*selfPath;
	NSTimer			*watchdogTimer;
	SUHost			*host;
}

- (void)	parentHasQuit;

- (void)	relaunch;
- (void)	install;

- (void)	watchdog:(NSTimer *)timer;

@end

@implementation TerminationListener

- (id) initWithExecutablePath:(const char *)execPath parentProcessId:(pid_t)ppid folderPath: (const char*)inFolderPath
		selfPath: (NSString*)inSelfPath
{
	self = [super init];
	if (self != nil)
	{
		executablePath = execPath;
		parentProcessId = ppid;
		folderPath = inFolderPath;
		selfPath = [inSelfPath retain];
		BOOL	alreadyTerminated = (getppid() == 1); // ppid is launchd (1) => parent terminated already
		
		if( alreadyTerminated )
			[self parentHasQuit];
		else
			watchdogTimer = [[NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(watchdog:) userInfo:nil repeats:YES] retain];
	}
	return self;
}


-(void)	dealloc
{
	[selfPath release];
	selfPath = nil;
	[watchdogTimer release];
	watchdogTimer = nil;
	[host release];
	host = nil;
	
	[super dealloc];
}


-(void)	parentHasQuit
{
	[watchdogTimer invalidate];
	
	if( folderPath )
		[self install];
	else
		[self relaunch];
}


- (void)watchdog:(NSTimer *)timer
{
	ProcessSerialNumber psn;
	if (GetProcessForPID(parentProcessId, &psn) == procNotFound)
		[self parentHasQuit];
}

- (void) relaunch
{
	NSString	*appPath = nil;
	if( !folderPath )
		appPath = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:executablePath length:strlen(executablePath)];
	else
		appPath = [host installationPath];
	[[NSWorkspace sharedWorkspace] openFile: appPath];
#if MAC_OS_X_VERSION_MIN_REQUIRED <= MAC_OS_X_VERSION_10_4
	if( folderPath )
    	[[NSFileManager defaultManager] removeFileAtPath: [SUInstaller updateFolder] handler: nil];
    [[NSFileManager defaultManager] removeFileAtPath: selfPath handler: nil];
#else
	if( folderPath )
    	[[NSFileManager defaultManager] removeItemAtPath: [SUInstaller updateFolder] error: NULL];
	[[NSFileManager defaultManager] removeItemAtPath: selfPath error: NULL];
#endif
	exit(EXIT_SUCCESS);
}


-(void)	install
{
	NSBundle			*theBundle = [NSBundle bundleWithPath: [NSString stringWithUTF8String: executablePath]];
	host = [[SUHost alloc] initWithBundle: theBundle];
	
	SUStatusController*	statusCtl = [[SUStatusController alloc] initWithHost: host];	// We quit anyway after we've installed, so leak this for now.
	[statusCtl setButtonTitle: SULocalizedString(@"Cancel Update",@"") target: nil action: Nil isDefault: NO];
	[statusCtl beginActionWithTitle: SULocalizedString(@"Installing update...",@"")
					maxProgressValue: 0 statusText: @""];
	[statusCtl showWindow: self];
	
	[SUInstaller installFromUpdateFolder: [NSString stringWithUTF8String: folderPath]
					overHost: host
					delegate: self synchronously: NO
					versionComparator: [SUStandardVersionComparator defaultComparator]];
}

- (void)installerFinishedForHost:(SUHost *)aHost
{
	[self relaunch];
}

- (void)installerForHost:(SUHost *)host failedWithError:(NSError *)error
{
	NSRunAlertPanel( @"", @"%@", @"OK", @"", @"", error );
	exit(EXIT_FAILURE);
}

@end

int main (int argc, const char * argv[])
{
	if( argc < 3 || argc > 4 )
		return EXIT_FAILURE;
	
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	ProcessSerialNumber		psn = { 0, kCurrentProcess };
	TransformProcessType( &psn, kProcessTransformToForegroundApplication );
	[[NSApplication sharedApplication] activateIgnoringOtherApps: YES];
		
	#if 0	// Cmdline tool
	NSString*	selfPath = nil;
	if( argv[0][0] == '/' )
		selfPath = [NSString stringWithUTF8String: argv[0]];
	else
	{
		selfPath = [[NSFileManager defaultManager] currentDirectoryPath];
		selfPath = [selfPath stringByAppendingPathComponent: [NSString stringWithUTF8String: argv[0]]];
	}
	#else
	NSString*	selfPath = [[NSBundle mainBundle] bundlePath];
	#endif
	
	[NSApplication sharedApplication];
	[[[TerminationListener alloc] initWithExecutablePath: (argc > 1) ? argv[1] : NULL
										parentProcessId: (argc > 2) ? atoi(argv[2]) : 0
										folderPath: (argc > 3) ? argv[3] : NULL
										selfPath: selfPath] autorelease];
	[[NSApplication sharedApplication] run];
	
	[pool drain];
	
	return EXIT_SUCCESS;
}
