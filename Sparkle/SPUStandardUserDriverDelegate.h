//
//  SPUStandardUserDriverDelegate.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/3/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#if __has_feature(modules)
#if __has_warning("-Watimport-in-framework-header")
#pragma clang diagnostic ignored "-Watimport-in-framework-header"
#endif
@import Foundation;
#else
#import <Foundation/Foundation.h>
#endif
#import <Sparkle/SUExport.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SUVersionDisplay;
@class SUAppcastItem;

/**
 A protocol for Sparkle's standard user driver's delegate
 
 This includes methods related to UI interactions
 */
SU_EXPORT @protocol SPUStandardUserDriverDelegate <NSObject>

@optional

/**
 Called before showing a modal alert window,
 to give the opportunity to hide attached windows that may get in the way.
 */
- (void)standardUserDriverWillShowModalAlert;

/**
 Called after showing a modal alert window,
 to give the opportunity to hide attached windows that may get in the way.
 */
- (void)standardUserDriverDidShowModalAlert;

/**
 Returns an object that formats version numbers for display to the user.
 If you don't implement this method or return @c nil, the standard version formatter will be used.
 */
- (_Nullable id <SUVersionDisplay>)standardUserDriverRequestsVersionDisplayer;

/**
 Handles showing the full release notes to the user.
 
 When a user checks for new updates and no new update is found, Sparkle will offer to show the application's version history to the user
 by providing a "Version History" button in the no new update available alert.
 
 If this delegate method is not implemented, Sparkle will instead offer to open the
 `fullReleaseNotesLink` (or `releaseNotesLink` if the former is unavailable) from the appcast's latest `item` in the user's web browser.
 
 If this delegate method is implemented, Sparkle will instead ask the delegate to show the full release notes to the user.
 A delegate may want to implement this method if they want to show in-app or offline release notes.
 
 @param item The appcast item corresponding to the latest version available.
 */
- (void)standardUserDriverShowVersionHistoryForAppcastItem:(SUAppcastItem *)item;

/**
 Specifies whether or not the download, extraction, and installing status windows allows to be minimized.
 
 By default, the status window showing the current status of the update (download, extraction, ready to install) is allowed to be minimized
 for regular application bundle updates.
 
 @return @c YES if the status window is allowed to be minimized (default behavior), otherwise @c NO.
 */
- (BOOL)standardUserDriverAllowsMinimizableStatusWindow;

/**
 Declares whether or not gentle scheduled update reminders are supported.
 
 The delegate may implement scheduled update reminders that are presented in a gentle manner by implementing
 `-standardUserDriverShouldShowAlertForScheduledUpdate:inFocusNow:`
 
 @return @c YES if gentle scheduled update reminders are implemented by standard user driver delegate, otherwise @c NO (default).
 */
- (BOOL)supportsGentleScheduledUpdateReminders;

/**
 Specifies if the standard user driver should handle showing a new update alert.
 
 This is called before the standard user driver handles showing an alert for a new update that is found.
 If you return @c YES, the update may not be shown immediately or in utmost focus. In these cases, @c inFocus is @c NO.
 
 For regular non-background applications, when @c inFocusNow is @c NO the standard user driver will prefer to show the update the next time
 the user comes back to the application. This is to minimize disrupting the user when they are actively using your application.
 Rarely, if an opportune time is unavailable after a threshold of elapsed time, the standard user driver may have to show an alert when the application is active however.
 When @c inFocusNow is @c YES the application is active, and either the updater / application just launched or the user's system was idle for an elapsed threshold.
 
 For non-background applications, when @c inFocusNow is @c NO, the standard user driver will show the update but not in utmost focus.
 This is to prevent a background application window from stealing focus from another foreground application without the user explicitly making this decision. If @c inFocusNow is @c YES the updater / application just launched.
 
 If you return @c NO the standard user driver will not handle showing the update alert but Sparkle's user driver session will still be running.
 At some point you may call `-[SPUStandardUpdateController checkForUpdates:]` or `-[SPUUpdater checkForUpdates]` to bring up the update alert in focus.
 In this case, you may want to show an additional UI indicator in your application that will show this update in focus.
 You may want to dismiss additional UI indicators in `-standardUserDriverWillCloseAlertForUpdate:`
 
 If you return @c YES you may still want to intercept this method. For example, you can publish a user notification when the application is not active.
 
 @param update The update the standard user driver should show.
 @param inFocusNow If @c inFocusNow is @c YES, then the standard user driver will show the update immediately in utmost focus. See discussion for more details.
 
 @return @c YES if the standard user should automatically handle showing the update (default behavior), otherwise @c NO.
 */
- (BOOL)standardUserDriverShouldShowAlertForScheduledUpdate:(SUAppcastItem *)update inFocusNow:(BOOL)inFocusNow;

/**
 Called before an alert window for an update is closed.
 
 The user has either started to install an update, dismiss it, or skip the update.
 
 This may be useful to intercept for dismissing custom UI indicators introduced when implementing
 `-standardUserDriverShouldShowAlertForScheduledUpdate:inFocusNow:`
 
 @param update The update corresponding to the update alert window the standard user driver is closing.
 */
- (void)standardUserDriverWillCloseAlertForUpdate:(SUAppcastItem *)update;

@end

NS_ASSUME_NONNULL_END
