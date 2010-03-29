//
//  SUCarbonUpdater.m
//  Sparkle
//
//  Created by Jack Small on 2/22/07.
//  Copyright 2007 Jack Small. All rights reserved.
//

#if SU_SPARKLE_FOR_CARBON

#import "SUCarbonUpdater.h"
#import "SUAppcast.h"
#import "SUAppcastItem.h"
#import "SUUpdateAlert.h"

#import <Carbon/Carbon.h>

#ifdef __LP64__
//
//	Manual inclusion of ProcessHICommand() prototype
//	
//	This API should be exported but is not.. 
//	<rdar://problem/6462981> Carbon: ProcessHICommand for 64-bit
//	Dec 22, 2008
//	
//	Future versions of Carbon.framework *will* export the prototype which will
//	produce an error on the line below.   At that point you can remove this workaround.

extern OSStatus ProcessHICommand(const HICommand* inCommand);

#endif	//	__LP64__


id					g_SharedSUUpdater = nil;

static  OSStatus  _SparkleEventHandler( EventHandlerCallRef inCallRef, EventRef inEvent, void *inUserData );
static  OSStatus  _SparkleEventHandler( EventHandlerCallRef inCallRef, EventRef inEvent, void *inUserData )
{
	#pragma unused ( inCallRef, inUserData )
	HICommand	command;
	OSStatus	err			= eventNotHandledErr;
	UInt32		eventClass	= GetEventClass( inEvent );
	UInt32		eventKind	= GetEventKind( inEvent );
	

	if( ( eventClass == kEventClassCommand ) && ( eventKind == kEventCommandUpdateStatus ) )
	{
		GetEventParameter( inEvent, kEventParamDirectObject, typeHICommand, NULL, sizeof(HICommand), NULL, &command );
		if ( command.commandID == kHICommandSparkleCheckForUpdates )
		{
#if !__LP64__
			if( command.attributes & kHICommandFromMenu )
			{
				if( SUSparkleIsUpdateInProgress() ) DisableMenuItem( command.menu.menuRef, command.menu.menuItemIndex );
				else EnableMenuItem( command.menu.menuRef, command.menu.menuItemIndex );
			}
#endif
			err  = noErr;
		}	
	}
	
	if( ( eventClass == kEventClassCommand ) && ( eventKind == kEventCommandProcess ) )
	{
		GetEventParameter( inEvent, kEventParamDirectObject, typeHICommand, NULL, sizeof(HICommand), NULL, &command );
		if ( command.commandID == kHICommandSparkleCheckForUpdates )
		{
			SUSparkleCheckForUpdates( TRUE );
			err  = noErr;
		}
	}

	return( err );
}

EventTargetRef	SUGetSparkleDefaultEventTarget( void )
{
#if __LP64__
	return GetEventDispatcherTarget();
#else
	return GetApplicationEventTarget();
#endif // __LP64__
}

void SUSparkleInitializeForCarbon( void )
{
	NSAutoreleasePool*	aPool;
    const  EventTypeSpec  applicationEvents[] =	{	{ kEventClassCommand, kEventCommandProcess },
													{ kEventClassCommand, kEventCommandUpdateStatus }
												};
	if( g_SharedSUUpdater == nil )
	{
		InstallEventHandler( SUGetSparkleDefaultEventTarget(), NewEventHandlerUPP(_SparkleEventHandler), GetEventTypeCount(applicationEvents), applicationEvents, 0, NULL );
		
		NSApplicationLoad();

		aPool = [[NSAutoreleasePool alloc] init];
		g_SharedSUUpdater = [[SUCarbonUpdater alloc] init];
		[g_SharedSUUpdater applicationDidFinishLaunching:nil];
		[aPool release];
	}
}

void SUSparkleCheckForUpdates( Boolean showUI )
{
	NSAutoreleasePool*	aPool;

	if( g_SharedSUUpdater != nil ) {
		aPool = [[NSAutoreleasePool alloc] init];
		if( showUI ) [g_SharedSUUpdater checkForUpdates:nil];
		else [g_SharedSUUpdater checkForUpdatesInBackground];
		[aPool release];
	}
}

void SUSparkleCheckWithInterval( double interval )
{
	NSAutoreleasePool*	aPool;

	if( g_SharedSUUpdater != nil ) {
		aPool = [[NSAutoreleasePool alloc] init];
		[g_SharedSUUpdater setUpdateCheckInterval:interval];
		[aPool release];
	}
}

void SUSparkleCheckStatus( EventTargetRef theEventTarget )
{
	NSAutoreleasePool*	aPool = [[NSAutoreleasePool alloc] init];
	EventTargetRef		aTarget = theEventTarget;
	
	if( aTarget == NULL ) 
		aTarget = SUGetSparkleDefaultEventTarget();

	[g_SharedSUUpdater setCarbonEventTarget:aTarget];
	[g_SharedSUUpdater checkForUpdatesInBackground];

	[aPool release];
}

Boolean SUSparkleIsUpdateInProgress( void )
{
	Boolean		outIsUpdating = FALSE;
	
	if( g_SharedSUUpdater != nil ) 
		outIsUpdating = [g_SharedSUUpdater updateInProgress];
	
	return outIsUpdating;
}

@implementation SUCarbonUpdater

- (id)init
{
	if( (self = [super init]) )
		carbonEventTarget = NULL;
	return self;
}

- (id)setCarbonEventTarget:(EventTargetRef)statusEventTarget
{
	carbonEventTarget = statusEventTarget;
	return self;
}

- (BOOL)updateInProgress
{
	return [super updateInProgress];
}

- (void)foundVersion:(NSString *)versionString isNewVersion:(Boolean)isNewVersion
{
	EventRef	theEvent;
	
	if( carbonEventTarget != NULL )
	{
		CreateEvent( kCFAllocatorDefault, kEventClassSparkle, kEventSparkleFoundVersion, 0, kEventAttributeUserEvent, &theEvent );
		SetEventParameter( theEvent, kEventParamPostTarget, typeEventTargetRef, sizeof(typeEventTargetRef), &carbonEventTarget );
		if( versionString != NULL ) SetEventParameter( theEvent, kEventParamSparkleVersion, typeCFStringRef, sizeof(CFStringRef), &versionString );
		SetEventParameter( theEvent, kEventParamSparkleIsNew, typeBoolean, sizeof(Boolean), &isNewVersion );
		
		PostEventToQueue( GetCurrentEventQueue(), theEvent, kEventPriorityStandard );
		
		ReleaseEvent( theEvent );
		
		carbonEventTarget = NULL;
	}
}

#pragma mark ### Delegate Functions ###

// Sent when a valid update is found by the update driver.
- (void)updater:(SUUpdater *)updater didFindValidUpdate:(SUAppcastItem *)update
	{	[self foundVersion:[update displayVersionString] isNewVersion:TRUE];	}

// Sent when a valid update is not found.
- (void)updaterDidNotFindUpdate:(SUUpdater *)update
	{	[self foundVersion:nil isNewVersion:FALSE];	}

// Responsible for quitting the app if special processing is necessary.
- (void)doQuitApplication
{
	// Slightly different quit mechanism for Carbon applications.
	OSStatus	quitResult = eventNotHandledErr;
	HICommand	quitCommand = { kEventAttributeNone, kHICommandSparkleQuitApplication };
	
	// First send custom Sparkle HICommand
	quitResult = ProcessHICommand( &quitCommand );
	
	// Second try regular Quit HICommand
	if( quitResult != noErr )
	{
		quitCommand.commandID = kHICommandQuit;
		quitResult = ProcessHICommand( &quitCommand );
	}

	// Third try using Core Foundation
	if( quitResult != noErr )
	{
		CFRunLoopRef	thisLoop = CFRunLoopGetCurrent();
		CFStringRef		thisMode = CFRunLoopCopyCurrentMode(thisLoop);
		if(  thisMode != NULL )
		{
			CFRelease( thisMode );
			CFRunLoopStop( thisLoop );
			quitResult = noErr;
		}
	}

	// Finally just bail
	if( quitResult != noErr ) ExitToShell();
}

// Called in response to an update dialog
- (void)updateAlert:(SUUpdateAlert *)updateAlert finishedWithChoice:(SUUpdateAlertChoice)updateChoice
{
	HICommand		updateCommand = { kEventAttributeNone, kHICommandSparkleDownloadingUpdate };
	HICommand		remindCommand = { kEventAttributeNone, kHICommandSparkleUpdateRemindLater };
	HICommand		skipItCommand = { kEventAttributeNone, kHICommandSparkleUpdateSkipVersion };
	
	HICommand		commandActual;
	
	switch ( updateChoice ) {
		case SUInstallUpdateChoice:
			commandActual = updateCommand;
			break;
		case SURemindMeLaterChoice:
			commandActual = remindCommand;
			break;
		case SUSkipThisVersionChoice:
			commandActual = skipItCommand;
			break;
		default:
			commandActual = updateCommand;
			break;
	}
	
	ProcessHICommand( &commandActual );
}

// Called when -abortUpdate is called.
- (void)updaterDidAbandonUpdate:(SUUpdater *)updater
{
	HICommand	aCommand = { kEventAttributeNone, kHICommandSparkleDownloadAbandoned };
	ProcessHICommand( &aCommand );
}

// Called when the update panel has been shown
- (void)updaterDidShowUpdatePanel:(SUUpdater *)updater
{
	HICommand	uCommand = { kEventAttributeNone, kHICommandSparkleUpdateShowPanel };
	ProcessHICommand( &uCommand );
}

@end		//	SUCarbonUpdater


#endif	//	SU_SPARKLE_FOR_CARBON


