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
    var testApplicationURL: NSURL? = nil
    var testApplicationBackupURL: NSURL? = nil
    var tempDirectoryURL: NSURL? = nil
    
    override func setUp()
    {
        super.setUp()
        
        let app = XCUIApplication()
        app.launch()
        
        XCTAssertFalse(app.dialogs["alert"].staticTexts["Update succeeded!"].exists, "Update is already installed; please do a clean build")
        
        // We need to grab the app URL so we can back up the app
        // When a successful test is over we'll revert the update
        // TODO: don't hardcode bundle ID?
        let runningApplications = NSRunningApplication.runningApplicationsWithBundleIdentifier("org.sparkle-project.SparkleTestApp")
        XCTAssertEqual(runningApplications.count, 1, "More than one running instance of the Test Application is found")
        let testApplicationURL = runningApplications[0].bundleURL!
        
        let tempDirectoryURL = try! NSFileManager.defaultManager().URLForDirectory(.ItemReplacementDirectory, inDomain: NSSearchPathDomainMask.UserDomainMask, appropriateForURL: testApplicationURL, create: true)
        
        let testApplicationBackupURL = tempDirectoryURL.URLByAppendingPathComponent(testApplicationURL.lastPathComponent!)
        
        try! NSFileManager.defaultManager().copyItemAtURL(testApplicationURL, toURL: testApplicationBackupURL)
        
        self.testApplicationURL = testApplicationURL
        self.testApplicationBackupURL = testApplicationBackupURL
        self.tempDirectoryURL = tempDirectoryURL
        
        // when we add more tests we don't want to continue after a failure
        // since a test can fail after the new app has been placed in
        self.continueAfterFailure = false
    }
    
    override func tearDown()
    {
        // Terminate just in case the app hasn't already quit
        XCUIApplication().terminate()
        
        // Revert our update with the original test application
        
        var resultingURL: NSURL? = nil
        try! NSFileManager.defaultManager().replaceItemAtURL(self.testApplicationURL!, withItemAtURL: self.testApplicationBackupURL!, backupItemName: nil, options: .UsingNewMetadataOnly, resultingItemURL: &resultingURL)
        
        do {
            try NSFileManager.defaultManager().removeItemAtURL(self.tempDirectoryURL!)
        } catch let error as NSError {
            NSLog("Failed to remove temporary directory \(self.tempDirectoryURL) with error: \(error)")
        }
        
        // The URL we get back from NSFileManager should be the same..
        XCTAssertEqual(self.testApplicationURL, resultingURL, "Test application was replaced, but at a different location")
        
        super.tearDown()
    }
    
    func testRegularUpdate()
    {
        let app = XCUIApplication()
        let menuBarsQuery = app.menuBars
            
        menuBarsQuery.menuBarItems["Sparkle Test App"].click()
        
        // If the update window already showed up automatically, this option will be disabled.
        // Even if it's disabled, attempting to click it will do no harm and continue on
        menuBarsQuery.menuItems["Check for Updates…"].click()
        
        app.dialogs["SUUpdateAlert"].buttons["Install Update"].click()
        app.buttons["Install and Relaunch"].click()
        
        // Our new updated app should be launched now
        // Grab another XCUIApplication instance rather than using the old one, just in case
        let updatedApp = XCUIApplication()
        
        // Check if we can click the "Update succeeded!" label rather than using the exists property
        // Checking the exists property doesn't reload the "cache" and as such the UI tests still would think we are
        // referring to the older app. Clicking does force the UI tests to find the new app however
        updatedApp.dialogs["alert"].staticTexts["Update succeeded!"].click()
        
        updatedApp.dialogs["alert"].buttons["OK"].click()
    }
}
