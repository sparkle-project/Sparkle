//
//  SUUnarchiverTest.swift
//  Sparkle
//
//  Created by Mayur Pawashe on 9/4/15.
//  Copyright © 2015 Sparkle Project. All rights reserved.
//

import XCTest

class SUUnarchiverTest: XCTestCase
{
    func unarchiveTestAppWithExtension(_ archiveExtension: String, password: String? = nil, resourceName: String = "SparkleTestCodeSignApp", extractedAppName: String = "SparkleTestCodeSignApp", expectingInstallationType installationType: String = SPUInstallationTypeApplication, expectingSuccess: Bool = true) {
        let appName = resourceName
        let archiveResourceURL = Bundle(for: type(of: self)).url(forResource: appName, withExtension: archiveExtension)!

        let fileManager = FileManager.default

        // Do not remove this temporary directory
        // If we do want to clean up and remove it (which isn't necessary but nice), we'd have to remove it
        // after *both* our unarchive success and failure calls below finish (they both have async completion blocks inside their implementation)
        let tempDirectoryURL = try! fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: URL(fileURLWithPath: NSHomeDirectory()), create: true)

        let unarchivedSuccessExpectation = super.expectation(description: "Unarchived Success (format: \(archiveExtension))")
        let unarchivedFailureExpectation = super.expectation(description: "Unarchived Failure (format: \(archiveExtension))")

        let extractedAppURL = tempDirectoryURL.appendingPathComponent(extractedAppName).appendingPathExtension("app")

        self.unarchiveTestAppWithExtension(archiveExtension, appName: appName, tempDirectoryURL: tempDirectoryURL, archiveResourceURL: archiveResourceURL, password: password, expectingInstallationType: installationType, expectingSuccess: expectingSuccess, testExpectation: unarchivedSuccessExpectation)
        self.unarchiveNonExistentFileTestFailureAppWithExtension(archiveExtension, tempDirectoryURL: tempDirectoryURL, password: password, expectingInstallationType: installationType, testExpectation: unarchivedFailureExpectation)

        super.waitForExpectations(timeout: 30.0, handler: nil)

        if !archiveExtension.hasSuffix("pkg") && expectingSuccess {
            XCTAssertTrue(fileManager.fileExists(atPath: extractedAppURL.path))
            XCTAssertEqual("6a60ab31430cfca8fb499a884f4a29f73e59b472", hashOfTree(extractedAppURL.path))
        }
    }

    func unarchiveNonExistentFileTestFailureAppWithExtension(_ archiveExtension: String, tempDirectoryURL: URL, password: String?, expectingInstallationType installationType: String, testExpectation: XCTestExpectation) {
        let tempArchiveURL = tempDirectoryURL.appendingPathComponent("error-invalid").appendingPathExtension(archiveExtension)
        let unarchiver = SUUnarchiver.unarchiver(forPath: tempArchiveURL.path, extractionDirectory: tempDirectoryURL.path, updatingHostBundlePath: nil, decryptionPassword: password, expectingInstallationType: installationType)!

        unarchiver.unarchive(completionBlock: {(error: Error?) -> Void in
            XCTAssertNotNil(error)
            testExpectation.fulfill()
        }, progressBlock: nil)
    }

    // swiftlint:disable function_parameter_count
    func unarchiveTestAppWithExtension(_ archiveExtension: String, appName: String, tempDirectoryURL: URL, archiveResourceURL: URL, password: String?, expectingInstallationType installationType: String, expectingSuccess: Bool, testExpectation: XCTestExpectation) {
        
        let unarchiver = SUUnarchiver.unarchiver(forPath: archiveResourceURL.path, extractionDirectory: tempDirectoryURL.path, updatingHostBundlePath: nil, decryptionPassword: password, expectingInstallationType: installationType)!

        unarchiver.unarchive(completionBlock: {(error: Error?) -> Void in
            if expectingSuccess {
                XCTAssertNil(error)
            } else {
                XCTAssertNotNil(error)
            }
            testExpectation.fulfill()
        }, progressBlock: nil)
    }

    func testUnarchivingZip()
    {
        self.unarchiveTestAppWithExtension("zip")
    }
    
    // This zip file has extraneous zero bytes added at the very end
    func testUnarchivingBadZipWithExtaneousTrailingBytes() {
        // We may receive a SIGPIPE error when writing data to a pipe
        // The Autoupdate installer ignores SIGPIPE too
        // We need to ignore it otherwise the xctest will terminate unexpectedly with exit code 13
        signal(SIGPIPE, SIG_IGN)
        
        self.unarchiveTestAppWithExtension("zip", resourceName: "SparkleTestCodeSignApp_bad_extraneous", extractedAppName: "SparkleTestCodeSignApp", expectingSuccess: false)
        
        signal(SIGPIPE, SIG_DFL)
    }
    
    func testUnarchivingBadZipWithMissingHeaderBytes() {
        // We may receive a SIGPIPE error when writing data to a pipe
        // The Autoupdate installer ignores SIGPIPE too
        // We need to ignore it otherwise the xctest will terminate unexpectedly with exit code 13
        signal(SIGPIPE, SIG_IGN)
        
        self.unarchiveTestAppWithExtension("zip", resourceName: "SparkleTestCodeSignApp_bad_header", extractedAppName: "SparkleTestCodeSignApp", expectingSuccess: false)
        
        signal(SIGPIPE, SIG_DFL)
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

#if SPARKLE_BUILD_DMG_SUPPORT
    func testUnarchivingHFSDmgWithLicenseAgreement()
    {
        self.unarchiveTestAppWithExtension("dmg")
    }

    func testUnarchivingEncryptedDmgWithLicenseAgreement()
    {
        self.unarchiveTestAppWithExtension("enc.dmg", password: "testpass")
    }
    
    func testUnarchivingAPFSDMG()
    {
        self.unarchiveTestAppWithExtension("dmg", resourceName: "SparkleTestCodeSign_apfs")
    }
#endif
    
#if SPARKLE_BUILD_PACKAGE_SUPPORT
    func testUnarchivingBarePackage()
    {
        self.unarchiveTestAppWithExtension("pkg", resourceName: "test", expectingInstallationType: SPUInstallationTypeGuidedPackage)
        
        self.unarchiveTestAppWithExtension("pkg", resourceName: "test", expectingInstallationType: SPUInstallationTypeInteractivePackage, expectingSuccess: false)
        
        self.unarchiveTestAppWithExtension("pkg", resourceName: "test", expectingInstallationType: SPUInstallationTypeApplication, expectingSuccess: false)
    }
#endif
}
