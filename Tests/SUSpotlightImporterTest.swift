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
        let fileManager = SUFileManager()
        let tempDirectoryURL = try! fileManager.makeTemporaryDirectoryAppropriate(forDirectoryURL: URL(fileURLWithPath: NSHomeDirectory()))

        let bundleDirectory = tempDirectoryURL.appendingPathComponent("bundle.app")
        try! fileManager.makeDirectory(at: bundleDirectory)

        let innerDirectory = bundleDirectory.appendingPathComponent("foo")
        try! fileManager.makeDirectory(at: innerDirectory)
        try! Data().write(to: (bundleDirectory.appendingPathComponent("bar")), options: .atomicWrite)

        let importerDirectory = innerDirectory.appendingPathComponent("baz.mdimporter")

        try! fileManager.makeDirectory(at: importerDirectory)
        try! fileManager.makeDirectory(at: innerDirectory.appendingPathComponent("flag"))

        try! Data().write(to: (importerDirectory.appendingPathComponent("file")), options: .atomicWrite)

        let oldFooDirectoryAttributes = try! FileManager.default.attributesOfItem(atPath: innerDirectory.path)
        let oldBarFileAttributes = try! FileManager.default.attributesOfItem(atPath: bundleDirectory.appendingPathComponent("bar").path)
        let oldImporterAttributes = try! FileManager.default.attributesOfItem(atPath: importerDirectory.path)
        let oldFlagAttributes = try! FileManager.default.attributesOfItem(atPath: innerDirectory.appendingPathComponent("flag").path)
        let oldFileInImporterAttributes = try! FileManager.default.attributesOfItem(atPath: importerDirectory.appendingPathComponent("file").path)

        sleep(1) // wait for clock to advance

        // Update spotlight bundles
        SUBinaryDeltaUnarchiver.updateSpotlightImporters(atBundlePath: bundleDirectory.path)

        let newFooDirectoryAttributes = try! FileManager.default.attributesOfItem(atPath: innerDirectory.path)
        XCTAssertEqual((newFooDirectoryAttributes[FileAttributeKey.modificationDate] as! Date).timeIntervalSince(oldFooDirectoryAttributes[FileAttributeKey.modificationDate] as! Date), 0)

        let newBarFileAttributes = try! FileManager.default.attributesOfItem(atPath: bundleDirectory.appendingPathComponent("bar").path)
        XCTAssertEqual((newBarFileAttributes[FileAttributeKey.modificationDate] as! Date).timeIntervalSince(oldBarFileAttributes[FileAttributeKey.modificationDate] as! Date), 0)

        let newImporterAttributes = try! FileManager.default.attributesOfItem(atPath: importerDirectory.path)
        XCTAssertGreaterThan((newImporterAttributes[FileAttributeKey.modificationDate] as! Date).timeIntervalSince(oldImporterAttributes[FileAttributeKey.modificationDate] as! Date), 0)

        let newFlagAttributes = try! FileManager.default.attributesOfItem(atPath: innerDirectory.appendingPathComponent("flag").path)
        XCTAssertEqual((newFlagAttributes[FileAttributeKey.modificationDate] as! Date).timeIntervalSince(oldFlagAttributes[FileAttributeKey.modificationDate] as! Date), 0)

        let newFileInImporterAttributes = try! FileManager.default.attributesOfItem(atPath: importerDirectory.appendingPathComponent("file").path)
        XCTAssertEqual((newFileInImporterAttributes[FileAttributeKey.modificationDate] as! Date).timeIntervalSince(oldFileInImporterAttributes[FileAttributeKey.modificationDate] as! Date), 0)

        try! fileManager.removeItem(at: tempDirectoryURL)
    }
}
