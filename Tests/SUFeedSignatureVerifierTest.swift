//
//  SUFeedSignatureVerifierTest.swift
//  Sparkle Unit Tests
//
//  Created on 12/30/25.
//  Copyright © 2025 Sparkle Project. All rights reserved.
//

import Foundation
import XCTest

class SUFeedSignatureVerifierTest: XCTestCase {
    var privateEdKey: Data!
    var publicEdKey: Data!
    
    override func setUp() {
        super.setUp()
        
        // These are the same private and public keys the Sparkle Test App uses
        
        let privateKeyBytes: [UInt8] = [
            200, 238, 135, 84, 10, 189, 3, 193,
            61, 208, 203, 30, 133, 47, 12, 22,
            19, 52, 252, 99, 110, 205, 209, 94,
            215, 144, 201, 70, 27, 162, 163, 108,
            0, 164, 68, 184, 226, 93, 121, 199,
            172, 17, 26, 64, 89, 68, 232, 41,
            2, 26, 245, 175, 158, 165, 42, 55,
            5, 97, 8, 243, 251, 164, 93, 9
        ]
        
        privateEdKey = Data(privateKeyBytes)
        
        let publicKeyBytes: [UInt8] = [
            121, 17, 79, 45, 155, 141, 51, 169,
            188, 110, 91, 102, 182, 147, 215, 225,
            252, 202, 110, 231, 200, 215, 62, 171,
            40, 145, 237, 128, 130, 44, 150, 89
        ]

        publicEdKey = Data(publicKeyBytes)
    }
    
    func testSigningAndValidatingAppcast() {
        let appcastURL = Bundle(for: SUFeedSignatureVerifierTest.self).url(forResource: "testappcast", withExtension: "xml")!
        
        let initialAppcastData = try! Data(contentsOf: appcastURL)
        
        let publicKeys = SUPublicKeys(ed: publicEdKey.base64EncodedString(), dsa: nil)
        let signatureVerifier = SUSignatureVerifier(publicKeys: publicKeys)
        
        // The content should be the same as the initial appcast data which isn't signed yet
        do {
            var outEdSignatureBase64: NSString?
            var outContentLength: UInt64 = 0
            let appcastContentData = SPUExtractAppcastContent(initialAppcastData, &outEdSignatureBase64, &outContentLength)
            
            XCTAssertNil(outEdSignatureBase64)
            XCTAssertEqual(outContentLength, 0)
            XCTAssertEqual(initialAppcastData, appcastContentData)
            
            // Trying to verify this file should fail when no signature is present
            let signatures = SUSignatures(ed: outEdSignatureBase64 as? String, dsa: nil)
            
            let verifierInformation = SPUVerifierInformation(expectedVersion: nil, expectedContentLength: outContentLength)
            verifierInformation.actualContentLength = UInt64(appcastContentData.count)
            
            do {
                try signatureVerifier.verifyData(appcastContentData, signatures: signatures, fileKind: "appcast", verifierInformation: verifierInformation)
                XCTFail("Verification should have failed on unsigned file")
            } catch {
                XCTAssertNotNil(error)
            }
        }
        
        // Add sign warning to appcast
        let appcastDataWithSigningWarning = addSignWarningToAppcast(data: initialAppcastData)
        XCTAssertGreaterThan(appcastDataWithSigningWarning.count, initialAppcastData.count)
        
        // Adding a signing warning to appcast shouldn't change anything
        do {
            let appcastDataWithSigningWarningAgain = addSignWarningToAppcast(data: appcastDataWithSigningWarning)
            XCTAssertEqual(appcastDataWithSigningWarningAgain, appcastDataWithSigningWarning)
        }
        
        let signedAppcastData = try! signAppcast(data: appcastDataWithSigningWarning, publicEdKey: publicEdKey, privateEdKey: privateEdKey)
        
        // XML data should be valid after signing
        _ = try! XMLDocument(data: signedAppcastData, options: XMLNode.Options())
        
        do {
            // Content of signed data should be same as content before it
            
            var outEdSignatureBase64: NSString?
            var outContentLength: UInt64 = 0
            let contentSignedAppcastData = SPUExtractAppcastContent(signedAppcastData, &outEdSignatureBase64, &outContentLength)
            
            XCTAssertNotNil(outEdSignatureBase64)
            XCTAssertEqual(outContentLength, UInt64(appcastDataWithSigningWarning.count))
            XCTAssertEqual(contentSignedAppcastData, appcastDataWithSigningWarning)
            
            // Verify the signature is correct
            
            let signatures = SUSignatures(ed: outEdSignatureBase64! as String, dsa: nil)
            let verifierInformation = SPUVerifierInformation(expectedVersion: nil, expectedContentLength: UInt64(appcastDataWithSigningWarning.count))
            verifierInformation.actualContentLength = UInt64(contentSignedAppcastData.count)
            
            try! signatureVerifier.verifyData(contentSignedAppcastData, signatures: signatures, fileKind: "appcast", verifierInformation: verifierInformation)
            
            // Insert a byte somewhere in the middle and ensure signing validation fails
            var modifiedInvalidSignedAppcastData = signedAppcastData
            modifiedInvalidSignedAppcastData.insert(62, at: signedAppcastData.count / 2)
            
            do {
                try signatureVerifier.verifyData(modifiedInvalidSignedAppcastData, signatures: signatures, fileKind: "appcast", verifierInformation: nil)
                XCTFail("Signature verification of modified appcast should have failed")
            } catch {
                XCTAssertNotNil(error)
            }
            
            // Re-signing should fix the signature however
            let modifiedSignedAppcastData = try! signAppcast(data: modifiedInvalidSignedAppcastData, publicEdKey: publicEdKey, privateEdKey: privateEdKey)
            
            let modifiedSignedAppcastDataContent = SPUExtractAppcastContent(modifiedSignedAppcastData, &outEdSignatureBase64, &outContentLength)
            
            let signaturesAfterModification = SUSignatures(ed: outEdSignatureBase64! as String, dsa: nil)
            try! signatureVerifier.verifyData(modifiedSignedAppcastDataContent, signatures: signaturesAfterModification, fileKind: "appcast", verifierInformation: nil)
        }
    }
    
    func testAddingSignWarningToHTMLReleaseNotes() {
        let releaseNotesURL = Bundle(for: SUFeedSignatureVerifierTest.self).url(forResource: "testreleasenotes", withExtension: "html")!
        
        let releaseNotesData = try! Data(contentsOf: releaseNotesURL)
        
        // Add sign warning to release notes
        let releaseNotesDataWithSigningWarning = updateHTMLCommentSigningWarningInReleaseNotes(data: releaseNotesData)!
        XCTAssertGreaterThan(releaseNotesDataWithSigningWarning.count, releaseNotesData.count)
        
        // Test that the content is the same minus the beginning signing warning
        do {
            let byteDifference = releaseNotesDataWithSigningWarning.count - releaseNotesData.count
            XCTAssertEqual(releaseNotesDataWithSigningWarning.subdata(in: releaseNotesDataWithSigningWarning.startIndex.advanced(by: byteDifference) ..< releaseNotesDataWithSigningWarning.endIndex), releaseNotesData)
        }
        
        // Test the content using SPUExtractReleaseNotesContent()
        do {
            let releaseNotesContent = SPUExtractReleaseNotesContent(releaseNotesDataWithSigningWarning)
            XCTAssertEqual(releaseNotesContent, releaseNotesData)
            
            // Extracting content again should return same data
            let releaseNotesContentAgain = SPUExtractReleaseNotesContent(releaseNotesContent)
            XCTAssertEqual(releaseNotesContentAgain, releaseNotesData)
        }
        
        // Test signing warning data without newline
        do {
            let signWarning = "<!-- sparkle-sign-warning:-->foobar"
            let signWarningData = Data(signWarning.utf8)
            
            let releaseNotesContent = SPUExtractReleaseNotesContent(signWarningData)
            XCTAssertEqual(releaseNotesContent, Data("foobar".utf8))
        }
        
        // Test minimal signing warning data
        do {
            let signWarning = "<!-- sparkle-sign-warning:-->"
            let signWarningData = Data(signWarning.utf8)
            
            let releaseNotesContent = SPUExtractReleaseNotesContent(signWarningData)
            XCTAssertEqual(releaseNotesContent.count, 0)
        }
        
        // Test minimal signing warning data with just a newline
        do {
            let signWarning = "<!-- sparkle-sign-warning:-->\n"
            let signWarningData = Data(signWarning.utf8)
            
            // This should skip over the newline
            let releaseNotesContent = SPUExtractReleaseNotesContent(signWarningData)
            XCTAssertEqual(releaseNotesContent.count, 0)
        }
    }
}
