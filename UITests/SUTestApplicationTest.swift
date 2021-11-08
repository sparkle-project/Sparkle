//
//  SUTestApplicationTest.swift
//  Sparkle
//
//  Created by Mayur Pawashe on 8/27/15.
//  Copyright © 2015 Sparkle Project. All rights reserved.
//

import XCTest

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

    // The debugger may catch the Test app receiving a SIGTERM signal when Sparkle quits the app before installing the new one
    // So you may have better luck running this test from the command line without the debugger attached:
    // xcodebuild -scheme UITests -configuration Debug test
    func testRegularUpdate()
    {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages",
            "(en)"
        ]
        app.launch()
        
        XCTAssertFalse(app.dialogs["alert"].staticTexts["Update succeeded!"].exists, "Update is already installed; please do a clean build")
        
        let initialRunningApplication = runningTestApplication()
        
        // Give some time for the Test App to initialize its web server, create an update, and start its updater
        sleep(60)
        
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

        app.windows["SUUpdateAlert"].buttons["Install Update"].click()
        
        // Give some time for the update to finish downloading / extracting
        sleep(30)
        
        app.windows["SUStatus"].buttons["Install and Relaunch"].click()

        // Wait for the new updated app to finish launching so we can test if it's the frontmost app
        sleep(10)

        // From now on, do not rely on XCUIApplication as it only works properly when the XCUITest framework launches the app.
        
        // Our new updated app should be launched now. Test if it's the active app and the old app is terminated.
        // We used to run into timing issues where the updated app sometimes may not show up as the frontmost one
        XCTAssertTrue(initialRunningApplication.isTerminated)

        let newRunningApplication = self.runningTestApplication()
        XCTAssertTrue(newRunningApplication.isActive)
        
        // Verify the new bundle version

        let infoCFDictionary = CFBundleCopyInfoDictionaryInDirectory(newRunningApplication.bundleURL! as CFURL)
        let infoDictionary = infoCFDictionary! as Dictionary
        
        let updatedVersion = infoDictionary[kCFBundleVersionKey] as! String
        XCTAssertEqual(updatedVersion, "2.0")
        
        // Clean up
        newRunningApplication.forceTerminate()
    }
}
