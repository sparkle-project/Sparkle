//
//  SUSpotlightImporterTest.swift
//  Sparkle
//
//  Created by Mayur Pawashe on 8/27/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

import XCTest

class SUSpotlightImporterTest: XCTestCase
{
    func testUpdatingSpotlightBundles()
    {
        let fileManager = SUFileManager.defaultManager()
        let tempDirectoryURL = try! fileManager.makeTemporaryDirectoryWithPreferredName("Sparkle Unit Test Data", appropriateForDirectoryURL: NSURL(fileURLWithPath: NSHomeDirectory()))
        
        let bundleDirectory = tempDirectoryURL.URLByAppendingPathComponent("bundle.app")
        try! fileManager.makeDirectoryAtURL(bundleDirectory)
        
        let innerDirectory = bundleDirectory.URLByAppendingPathComponent("foo")
        try! fileManager.makeDirectoryAtURL(innerDirectory)
        try! NSData().writeToURL(bundleDirectory.URLByAppendingPathComponent("bar"), options: .AtomicWrite)
        
        let importerDirectory = innerDirectory.URLByAppendingPathComponent("baz.mdimporter")
        
        try! fileManager.makeDirectoryAtURL(importerDirectory)
        try! fileManager.makeDirectoryAtURL(innerDirectory.URLByAppendingPathComponent("flag"))
        
        try! NSData().writeToURL(importerDirectory.URLByAppendingPathComponent("file"), options: .AtomicWrite)
        
        let oldFooDirectoryAttributes = try! NSFileManager.defaultManager().attributesOfItemAtPath(innerDirectory.path!)
        let oldBarFileAttributes = try! NSFileManager.defaultManager().attributesOfItemAtPath(bundleDirectory.URLByAppendingPathComponent("bar").path!)
        let oldImporterAttributes = try! NSFileManager.defaultManager().attributesOfItemAtPath(importerDirectory.path!)
        let oldFlagAttributes = try! NSFileManager.defaultManager().attributesOfItemAtPath(innerDirectory.URLByAppendingPathComponent("flag").path!)
        let oldFileInImporterAttributes = try! NSFileManager.defaultManager().attributesOfItemAtPath(importerDirectory.URLByAppendingPathComponent("file").path!)
        
        sleep(1) // wait for clock to advance
        
        // Update spotlight bundles
        SUBinaryDeltaUnarchiver.updateSpotlightImportersAtBundlePath(bundleDirectory.path!)
        
        let newFooDirectoryAttributes = try! NSFileManager.defaultManager().attributesOfItemAtPath(innerDirectory.path!)
        XCTAssertEqual((newFooDirectoryAttributes[NSFileModificationDate] as! NSDate).timeIntervalSinceDate(oldFooDirectoryAttributes[NSFileModificationDate] as! NSDate), 0)
        
        let newBarFileAttributes = try! NSFileManager.defaultManager().attributesOfItemAtPath(bundleDirectory.URLByAppendingPathComponent("bar").path!)
        XCTAssertEqual((newBarFileAttributes[NSFileModificationDate] as! NSDate).timeIntervalSinceDate(oldBarFileAttributes[NSFileModificationDate] as! NSDate), 0)
        
        let newImporterAttributes = try! NSFileManager.defaultManager().attributesOfItemAtPath(importerDirectory.path!)
        XCTAssertGreaterThan((newImporterAttributes[NSFileModificationDate] as! NSDate).timeIntervalSinceDate(oldImporterAttributes[NSFileModificationDate] as! NSDate), 0)
        
        let newFlagAttributes = try! NSFileManager.defaultManager().attributesOfItemAtPath(innerDirectory.URLByAppendingPathComponent("flag").path!)
        XCTAssertEqual((newFlagAttributes[NSFileModificationDate] as! NSDate).timeIntervalSinceDate(oldFlagAttributes[NSFileModificationDate] as! NSDate), 0)
        
        let newFileInImporterAttributes = try! NSFileManager.defaultManager().attributesOfItemAtPath(importerDirectory.URLByAppendingPathComponent("file").path!)
        XCTAssertEqual((newFileInImporterAttributes[NSFileModificationDate] as! NSDate).timeIntervalSinceDate(oldFileInImporterAttributes[NSFileModificationDate] as! NSDate), 0)
        
        try! fileManager.removeItemAtURL(tempDirectoryURL)
    }
}
