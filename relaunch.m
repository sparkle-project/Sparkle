
#import <AppKit/AppKit.h>

#include <unistd.h>

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
	if (self != nil)
	{
		executablePath = execPath;
		parentProcessId = ppid;
		if (getppid() == 1) // ppid is launchd (1) => parent terminated already
			[self relaunch];
		[NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(watchdog:) userInfo:nil repeats:YES];
	}
	return self;
}

- (void)watchdog:(NSTimer *)timer
{
	ProcessSerialNumber psn;
	if (GetProcessForPID(parentProcessId, &psn) == procNotFound)
		[self relaunch];
}

- (void) relaunch
{
	[[NSWorkspace sharedWorkspace] openFile:[[NSFileManager defaultManager] stringWithFileSystemRepresentation:executablePath length:strlen(executablePath)]];
	[[NSFileManager defaultManager] removeFileAtPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"relaunch"] handler:nil];
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
	
	[pool drain];
	
	return EXIT_SUCCESS;
}
