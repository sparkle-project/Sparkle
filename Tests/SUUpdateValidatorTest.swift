//
//  SUUpdateValidatorTest.swift
//  Sparkle
//
//  Created by Jordan Rose on 2020-06-13.
//  Copyright © 2020 Sparkle Project. All rights reserved.
//

import Foundation
import XCTest

class SUUpdateValidatorTest: XCTestCase {
    enum BundleConfig: String, CaseIterable, Equatable {
        case none = "None"
        case dsaOnly = "DSAOnly"
        case edOnly = "EDOnly"
        case both = "Both"
        case codeSignedOnly = "CodeSignedOnly"
        case codeSignedBoth = "CodeSignedBoth"
        case codeSignedOnlyNew = "CodeSignedOnlyNew"
        case codeSignedBothNew = "CodeSignedBothNew"
        case codeSignedOldED = "CodeSignedOldED"
        case codeSignedInvalidOnly = "CodeSignedInvalidOnly"
        case codeSignedInvalid = "CodeSignedInvalid"

        var hasAnyKeys: Bool {
            switch self {
            case .none, .codeSignedOnly, .codeSignedOnlyNew, .codeSignedInvalidOnly:
                return false
            case .dsaOnly, .edOnly, .both, .codeSignedBoth, .codeSignedBothNew, .codeSignedOldED, .codeSignedInvalid:
                return true
            }
        }
    }

    struct SignatureConfig: CaseIterable, Equatable, CustomDebugStringConvertible {
        enum State: CaseIterable, Equatable {
            case none, invalid, valid
        }

        var dsa: State
        var ed: State

        static let allCases: [SignatureConfig] = State.allCases.flatMap { dsaState in
            State.allCases.map { edState in
                SignatureConfig(dsa: dsaState, ed: edState)
            }
        }

        var debugDescription: String {
            return "(dsa: \(self.dsa), ed: \(self.ed))"
        }
    }

    func bundle(_ config: BundleConfig) -> Bundle {
        let testBundle = Bundle(for: SUUpdateValidatorTest.self)
        let configBundleURL = testBundle.url(forResource: config.rawValue, withExtension: "bundle", subdirectory: "SUUpdateValidatorTest")!
        return Bundle(url: configBundleURL)!
    }

    func signatures(_ config: SignatureConfig) -> SUSignatures {
        let dsaSig: String?
        switch config.dsa {
        case .none: dsaSig = nil
        case .invalid: dsaSig = "MCwCFCIHCiYYkfZavNzTitTW5tlRp/k5AhQ40poFytqcVhIYdCxQznaXeJPJDQ=="
        case .valid: dsaSig = "MCwCFCIHCIYYkfZavNzTitTW5tlRp/k5AhQ40poFytqcVhIYdCxQznaXeJPJDQ=="
        }

        let edSig: String?
        switch config.ed {
        case .none: edSig = nil
        case .invalid: edSig = "wTcpXCgWoa4NrJpsfzS61FXJIbv963//12U2ef9xstzVOLPHYK2N4/ojgpDV5N1/NGG1uWMBgK+kEWp0Z5zMDQ=="
        case .valid: edSig = "EIawm2YkDZ2gBfkEMF2+1VuuTeXnCGZOdnMdVgPPvDZioq7bvDayXqKkIIzSjKMmeFdcFJOHdnba5ZV60+gPBw=="
        }

        return SUSignatures(dsa: dsaSig, ed: edSig)
    }

    var signedTestFilePath: String {
        let testBundle = Bundle(for: SUUpdateValidatorTest.self)
        return testBundle.path(forResource: "signed-test-file", ofType: "txt")!
    }

    func testPrevalidation(bundle bundleConfig: BundleConfig, signatures signatureConfig: SignatureConfig, expectedResult: Bool, line: UInt = #line) {
        let host = SUHost(bundle: self.bundle(bundleConfig))
        let signatures = self.signatures(signatureConfig)

        let validator = SUUpdateValidator(downloadPath: self.signedTestFilePath, signatures: signatures, host: host)

        let result = validator.validateDownloadPath()
        XCTAssertEqual(result, expectedResult, "bundle: \(bundleConfig), signatures: \(signatureConfig)", line: line)
    }

    func testPrevalidation() {
        for signatureConfig in SignatureConfig.allCases {
            testPrevalidation(bundle: .none, signatures: signatureConfig, expectedResult: false)
            testPrevalidation(bundle: .dsaOnly, signatures: signatureConfig, expectedResult: signatureConfig.dsa == .valid)
            testPrevalidation(bundle: .edOnly, signatures: signatureConfig, expectedResult: signatureConfig.ed == .valid)
            testPrevalidation(bundle: .both, signatures: signatureConfig, expectedResult: signatureConfig.dsa == .valid && signatureConfig.ed != .invalid)
        }
    }

    func testPostValidation(oldBundle oldBundleConfig: BundleConfig, newBundle newBundleConfig: BundleConfig, signatures signatureConfig: SignatureConfig, expectedResult: Bool, line: UInt = #line) {
        let oldBundle = self.bundle(oldBundleConfig)
        let host = SUHost(bundle: oldBundle)
        let signatures = self.signatures(signatureConfig)

        let validator = SUUpdateValidator(downloadPath: self.signedTestFilePath, signatures: signatures, host: host)

        let updateDirectory = temporaryDirectory("SUUpdateValidatorTest")!
        defer { try! FileManager.default.removeItem(atPath: updateDirectory) }
        let newBundle = self.bundle(newBundleConfig)
        try! FileManager.default.copyItem(at: newBundle.bundleURL, to: URL(fileURLWithPath: updateDirectory).appendingPathComponent(oldBundle.bundleURL.lastPathComponent))

        let result = validator.validate(withUpdateDirectory: updateDirectory)
        XCTAssertEqual(result, expectedResult, "oldBundle: \(oldBundleConfig), newBundle: \(newBundleConfig), signatures: \(signatureConfig)", line: line)
    }

    func testPostValidation(bundle bundleConfig: BundleConfig, signatures signatureConfig: SignatureConfig, expectedResult: Bool, line: UInt = #line) {
        testPostValidation(oldBundle: bundleConfig, newBundle: bundleConfig, signatures: signatureConfig, expectedResult: expectedResult, line: line)
    }

    func testPostValidationWithoutCodeSigning() {
        for signatureConfig in SignatureConfig.allCases {
            testPostValidation(bundle: .none, signatures: signatureConfig, expectedResult: false)
            testPostValidation(bundle: .dsaOnly, signatures: signatureConfig, expectedResult: signatureConfig.dsa == .valid)
            testPostValidation(bundle: .edOnly, signatures: signatureConfig, expectedResult: signatureConfig.ed == .valid)
            testPostValidation(bundle: .both, signatures: signatureConfig, expectedResult: signatureConfig.dsa == .valid && signatureConfig.ed != .invalid)
        }
    }

    func testPostValidationWithCodeSigning() {
        for signatureConfig in SignatureConfig.allCases {
            testPostValidation(bundle: .codeSignedOnly, signatures: signatureConfig, expectedResult: true)
            testPostValidation(bundle: .codeSignedBoth, signatures: signatureConfig, expectedResult: signatureConfig.dsa == .valid && signatureConfig.ed != .invalid)

            testPostValidation(bundle: .codeSignedInvalidOnly, signatures: signatureConfig, expectedResult: false)
            testPostValidation(bundle: .codeSignedInvalid, signatures: signatureConfig, expectedResult: false)
        }
    }

    func testPostValidationWithKeyRemoval() {
        for bundleConfig in BundleConfig.allCases {
            testPostValidation(oldBundle: .dsaOnly, newBundle: bundleConfig, signatures: SignatureConfig(dsa: .valid, ed: .valid), expectedResult: bundleConfig.hasAnyKeys && bundleConfig != .codeSignedInvalid)
            testPostValidation(oldBundle: .edOnly, newBundle: bundleConfig, signatures: SignatureConfig(dsa: .valid, ed: .valid), expectedResult: bundleConfig.hasAnyKeys && bundleConfig != .codeSignedInvalid)
            testPostValidation(oldBundle: .both, newBundle: bundleConfig, signatures: SignatureConfig(dsa: .valid, ed: .valid), expectedResult: bundleConfig.hasAnyKeys && bundleConfig != .codeSignedInvalid)
            testPostValidation(oldBundle: .codeSignedBoth, newBundle: bundleConfig, signatures: SignatureConfig(dsa: .valid, ed: .valid), expectedResult: bundleConfig.hasAnyKeys && bundleConfig != .codeSignedInvalid)
        }
    }

    func testPostValidationWithKeyRotation() {
        for signatureConfig in SignatureConfig.allCases {
            let signatureIsValid = signatureConfig.dsa == .valid && (signatureConfig.ed == .valid || signatureConfig.ed == .none)

            // It's okay to add DSA keys or add code signing.
            testPostValidation(oldBundle: .codeSignedOnly, newBundle: .codeSignedBoth, signatures: signatureConfig, expectedResult: signatureIsValid)
            testPostValidation(oldBundle: .both, newBundle: .codeSignedBoth, signatures: signatureConfig, expectedResult: signatureIsValid)

            // If you want to change your code signing, you have to be using both forms of auth.
            testPostValidation(oldBundle: .codeSignedOnly, newBundle: .codeSignedOnlyNew, signatures: signatureConfig, expectedResult: false)
            testPostValidation(oldBundle: .codeSignedBoth, newBundle: .codeSignedOnlyNew, signatures: signatureConfig, expectedResult: false)
            testPostValidation(oldBundle: .codeSignedOnly, newBundle: .codeSignedBothNew, signatures: signatureConfig, expectedResult: false)
            testPostValidation(oldBundle: .codeSignedBoth, newBundle: .codeSignedBothNew, signatures: signatureConfig, expectedResult: signatureIsValid)

            // If you want to change your keys, you have to be using both forms of auth.
            testPostValidation(oldBundle: .codeSignedOldED, newBundle: .codeSignedOnly, signatures: signatureConfig, expectedResult: false)
            testPostValidation(oldBundle: .codeSignedOldED, newBundle: .codeSignedBoth, signatures: signatureConfig, expectedResult: signatureIsValid)

            // You can't change two things at once.
            testPostValidation(oldBundle: .codeSignedOldED, newBundle: .codeSignedBothNew, signatures: signatureConfig, expectedResult: false)

            // It's permitted to remove code signing too.
            testPostValidation(oldBundle: .codeSignedBoth, newBundle: .both, signatures: signatureConfig, expectedResult: signatureIsValid)
        }
    }
}
