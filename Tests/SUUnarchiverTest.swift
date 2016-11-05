//
//  SUUnarchiverTest.swift
//  Sparkle
//
//  Created by Mayur Pawashe on 9/4/15.
//  Copyright © 2015 Sparkle Project. All rights reserved.
//

import XCTest

class SUUnarchiverTest: XCTestCase, SUUnarchiverDelegate
{
    var password: String? = nil
    var unarchivedExpectation: XCTestExpectation? = nil
    var unarchivedResult: Bool = false
    
    func unarchiver(_ unarchiver: SUUnarchiver!, extractedProgress progress: Double)
    {
    }
    
    func unarchiverDidFail(_ unarchiver: SUUnarchiver!)
    {
        self.unarchivedResult = false
        self.unarchivedExpectation!.fulfill()
    }
    
    func unarchiverDidFinish(_ unarchiver: SUUnarchiver!)
    {
        self.unarchivedResult = true
        self.unarchivedExpectation!.fulfill()
    }
    
    func unarchiveTestAppWithExtension(_ archiveExtension: String)
    {
        let appName = "SparkleTestCodeSignApp"
        let archiveResourceURL = Bundle(for: type(of: self)).url(forResource: appName, withExtension: archiveExtension)!
        
        let fileManager = FileManager.default
        
        let tempDirectoryURL = try! fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: URL(fileURLWithPath: NSHomeDirectory()), create: true)
        defer {
            try! fileManager.removeItem(at: tempDirectoryURL)
        }
        
        let tempArchiveURL = tempDirectoryURL.appendingPathComponent(archiveResourceURL.lastPathComponent)
        let extractedAppURL = tempDirectoryURL.appendingPathComponent(appName).appendingPathExtension("app")
        
        try! fileManager.copyItem(at: archiveResourceURL, to: tempArchiveURL)
        
        self.unarchivedExpectation = super.expectation(description: "Unarchived Application (format: \(archiveExtension))")
        
        let unarchiver = SUUnarchiver(forPath: tempArchiveURL.path, updatingHostBundlePath: nil, withPassword: self.password)

        unarchiver?.delegate = self
        unarchiver?.start()
        
        super.waitForExpectations(timeout: 7.0, handler: nil)
        
        XCTAssertTrue(self.unarchivedResult)
        XCTAssertTrue(fileManager.fileExists(atPath: extractedAppURL.path))
        
        XCTAssertEqual("6a60ab31430cfca8fb499a884f4a29f73e59b472", hashOfTree(extractedAppURL.path))
    }

    func testUnarchivingZip()
    {
        self.unarchiveTestAppWithExtension("zip")
    }
    
    func testUnarchivingTarDotGz()
    {
        self.unarchiveTestAppWithExtension("tar.gz")
    }
    
    func testUnarchivingTar()
    {
        self.unarchiveTestAppWithExtension("tar")
    }
    
    func testUnarchivingTarDotBz2()
    {
        self.unarchiveTestAppWithExtension("tar.bz2")
    }
    
    func testUnarchivingTarDotXz()
    {
        self.unarchiveTestAppWithExtension("tar.xz")
    }
    
    func testUnarchivingDmg()
    {
        self.unarchiveTestAppWithExtension("dmg")
    }

    func testUnarchivingEncryptedDmg()
    {
        self.password = "testpass";
        self.unarchiveTestAppWithExtension("enc.dmg")
    }
}
