
#import <AppKit/AppKit.h>

@interface TerminationListener : NSObject
{
	const char *executablePath;
	pid_t parentProcessId;
}

- (void) relaunch;

@end

@implementation TerminationListener

- (id) initWithExecutablePath:(const char *)execPath parentProcessId:(pid_t)ppid
{
	self = [super init];
	if (self != nil) {
		executablePath = execPath;
		parentProcessId = ppid;
		
		[[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(applicationDidTerminate:) name:NSWorkspaceDidTerminateApplicationNotification object:nil];
		if (getppid() == 1) {
			// ppid is launchd (1) => parent terminated already
			[self relaunch];
		}
		
		ProcessSerialNumber psn;
		if (GetProcessForPID(ppid, &psn) == procNotFound) {
			[self relaunch];
		}
	}
	return self;
}

- (void) applicationDidTerminate:(NSNotification *)notification
{
	if (parentProcessId == [[[notification userInfo] valueForKey:@"NSApplicationProcessIdentifier"] intValue]) {
		// parent just terminated
		[self relaunch];
	}
}

- (void) relaunch
{
	[[NSWorkspace sharedWorkspace] launchApplication:[NSString stringWithUTF8String:executablePath]];	
	exit(0);
}

@end

int main (int argc, const char * argv[])
{
	if (argc != 3) return EXIT_FAILURE;
	
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	[NSApplication sharedApplication];
	[[[TerminationListener alloc] initWithExecutablePath:argv[1] parentProcessId:atoi(argv[2])] autorelease];
	[[NSApplication sharedApplication] run];
	
	[pool release];
	
	return EXIT_SUCCESS;
}
