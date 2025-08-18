//
//  SUTestApplicationTest.swift
//  Sparkle
//
//  Created by Mayur Pawashe on 8/27/15.
//  Copyright © 2015 Sparkle Project. All rights reserved.
//

import XCTest

// The debugger may catch the Test app receiving a SIGTERM signal when Sparkle quits the app before installing the new one
// So you may have better luck running these tests from the command line without the debugger attached:
// xcodebuild -scheme UITests -configuration Debug test
class SUTestApplicationTest: XCTestCase
{
    // TODO: don't hardcode bundle ID?
    let TEST_APP_BUNDLE_ID = "org.sparkle-project.SparkleTestApp"

    func runningTestApplication() -> NSRunningApplication
    {
        let runningApplications = NSRunningApplication.runningApplications(withBundleIdentifier: TEST_APP_BUNDLE_ID)
        XCTAssertEqual(runningApplications.count, 1, "More than one or zero running instances of the Test Application are found")
        return runningApplications[0]
    }

    func runTestApplication(testMode: String, automatic: Bool, expectedFinalVersion: String, launchSleep: UInt32, extractSleep: UInt32) {
        let app = XCUIApplication()
        app.launchArguments = [
            "-SUHasLaunchedBefore",
            automatic ? "YES" : "NO",
            "-SUEnableAutomaticChecks",
            automatic ? "YES" : "NO",
            "-SUAutomaticallyUpdate",
            automatic ? "YES" : "NO",
            "-SUScheduledCheckInterval",
            "60"
        ]
        app.launchEnvironment = ["TEST_MODE": testMode]
        app.launch()
        
        XCTAssertFalse(app.dialogs["alert"].staticTexts["Update succeeded!"].exists, "Update is already installed; please do a clean build")
        
        let initialRunningApplication = runningTestApplication()
        let bundleURL = initialRunningApplication.bundleURL!
        
        // Give some time for the Test App to initialize its web server, create an update, and start its updater
        sleep(launchSleep)
        
        let menuBarsQuery = app.menuBars
        menuBarsQuery.menuBarItems["Sparkle Test App"].click()
        
        let checkForUpdatesMenuItem = menuBarsQuery.menuItems["Check for Updates…"]
        if checkForUpdatesMenuItem.isEnabled {
            checkForUpdatesMenuItem.click()
        } else {
            // We haven't checked for updates in a while so an automatic check was already done
            // in this case click the main menu again to deactivate it
            menuBarsQuery.menuBarItems["Sparkle Test App"].click()
        }
        
        if !automatic {
            app.windows["SUUpdateAlert"].buttons["SPUUserUpdateChoiceInstall"].click()
        
            // Give some time for the update to finish downloading / extracting
            sleep(extractSleep)
            
            app.windows["SUStatus"].buttons["SUStatusInstallAndRelaunch"].click()
        } else {
            XCTAssertTrue(app.windows["SUUpdateAlert"].buttons["SPUUserUpdateChoiceInstall"].exists)
            
            // The app should install automatically on termination
            app.terminate()
        }
        
        // Wait for the new updated app to finish launching so we can test if it's the frontmost app
        sleep(10)

        // From now on, do not rely on XCUIApplication as it only works properly when the XCUITest framework launches the app.
        
        // Our new updated app should be launched now. Test if it's the active app and the old app is terminated.
        // We used to run into timing issues where the updated app sometimes may not show up as the frontmost one
        XCTAssertTrue(initialRunningApplication.isTerminated)
        
        // Verify the new bundle version

        let infoCFDictionary = CFBundleCopyInfoDictionaryInDirectory(bundleURL as CFURL)
        let infoDictionary = infoCFDictionary! as Dictionary
        
        let updatedVersion = infoDictionary[kCFBundleVersionKey] as! String
        XCTAssertEqual(updatedVersion, expectedFinalVersion)
        
        // Clean up
        if !automatic {
            let newRunningApplication = self.runningTestApplication()
            XCTAssertTrue(newRunningApplication.isActive)
            
            newRunningApplication.forceTerminate()
        }
        
        sleep(10)
    }
    
    func test1RegularUpdate() {
        runTestApplication(testMode: "REGULAR", automatic: false, expectedFinalVersion: "2.0", launchSleep: 60, extractSleep: 30)
    }
    
    func test2DeltaUpdate() {
        runTestApplication(testMode: "DELTA", automatic: false, expectedFinalVersion: "2.1", launchSleep: 75, extractSleep: 45)
    }
    
    func test3AutomaticUpdate() {
        runTestApplication(testMode: "AUTOMATIC", automatic: true, expectedFinalVersion: "2.2", launchSleep: 75, extractSleep: 30)
    }
}
