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
            case .edOnly, .both, .codeSignedBoth, .codeSignedBothNew, .codeSignedOldED, .codeSignedInvalid:
                return true
            case .dsaOnly:
                return true
            }
        }
        
        var isValidCodeSigned: Bool {
            switch self {
            case .codeSignedOnly, .codeSignedOnlyNew, .codeSignedBothNew, .codeSignedOldED, .codeSignedBoth:
                return true
            case .none, .dsaOnly, .edOnly, .both, .codeSignedInvalid, .codeSignedInvalidOnly:
                return false
            }
        }
    }

    struct SignatureConfig: CaseIterable, Equatable, CustomDebugStringConvertible {
        enum State: CaseIterable, Equatable {
            case none, invalid, invalidFormat, valid
        }

        var ed: State
#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
        var dsa: State
#endif

        static let allCases: [SignatureConfig] = State.allCases.flatMap { dsaState in
            State.allCases.map { edState in
#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
                SignatureConfig(ed: edState, dsa: dsaState)
#else
                SignatureConfig(ed: edState)
#endif
            }
        }

        var debugDescription: String {
#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
            return "(ed: \(self.ed), dsa: \(self.dsa))"
#else
            return "(ed: \(self.ed))"
#endif
        }
    }

    func bundle(_ config: BundleConfig) -> Bundle {
        let testBundle = Bundle(for: SUUpdateValidatorTest.self)
        let configBundleURL = testBundle.url(forResource: config.rawValue, withExtension: "bundle", subdirectory: "SUUpdateValidatorTest")!
        return Bundle(url: configBundleURL)!
    }

    func signatures(_ config: SignatureConfig) -> SUSignatures {
#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
        let dsaSig: String?
        switch config.dsa {
        case .none: dsaSig = nil
        case .invalid: dsaSig = "ABwCFCIHCIYYkfZavNzTitTW5tlRp/k5AhQ40poFytqcVhIYdCxQznaXeJPJDQ=="
        // Use some invalid base64 strings
        case .invalidFormat: dsaSig = "%%wCFCIHCIYYkfZavNzTitTW5tlRp/k5AhQ40poFytqcVhIYdCxQznaXeJPJDQ=="
        case .valid: dsaSig = "MCwCFCIHCIYYkfZavNzTitTW5tlRp/k5AhQ40poFytqcVhIYdCxQznaXeJPJDQ=="
        }
#endif

        let edSig: String?
        switch config.ed {
        case .none: edSig = nil
        case .invalid: edSig = "wTcpXCgWoa4NrJpsfzS61FXJIbv963//12U2ef9xstzVOLPHYK2N4/ojgpDV5N1/NGG1uWMBgK+kEWp0Z5zMDQ=="
        // Use some invalid base64 strings
        case .invalidFormat: edSig = "%%cpXCgWoa4NrJpsfzS61FXJIbv963//12U2ef9xstzVOLPHYK2N4/ojgpDV5N1/NGG1uWMBgK+kEWp0Z5zMDQ=="
        case .valid: edSig = "EIawm2YkDZ2gBfkEMF2+1VuuTeXnCGZOdnMdVgPPvDZioq7bvDayXqKkIIzSjKMmeFdcFJOHdnba5ZV60+gPBw=="
        }

#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
        return SUSignatures(ed: edSig, dsa: dsaSig)
#else
        return SUSignatures(ed: edSig)
#endif
    }

    var signedTestFilePath: String {
        let testBundle = Bundle(for: SUUpdateValidatorTest.self)
        return testBundle.path(forResource: "signed-test-file", ofType: "txt")!
    }

    func testPrevalidation(bundle bundleConfig: BundleConfig, signatures signatureConfig: SignatureConfig, expectedResult: Bool, line: UInt = #line) {
        let host = SUHost(bundle: self.bundle(bundleConfig))
        let signatures = self.signatures(signatureConfig)
        let validator = SUUpdateValidator(downloadPath: self.signedTestFilePath, signatures: signatures, host: host, verifierInformation: nil)

        let result = (try? validator.validateHostHasPublicKeys()) != nil && (try? validator.validateDownloadPathWithFallback(onCodeSigning: false)) != nil
        XCTAssertEqual(result, expectedResult, "bundle: \(bundleConfig), signatures: \(signatureConfig)", line: line)
    }

    func testPrevalidation() {
        for signatureConfig in SignatureConfig.allCases {
            testPrevalidation(bundle: .none, signatures: signatureConfig, expectedResult: false)
#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
            testPrevalidation(bundle: .dsaOnly, signatures: signatureConfig, expectedResult: signatureConfig.dsa == .valid)
#endif
#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
            testPrevalidation(bundle: .edOnly, signatures: signatureConfig, expectedResult: signatureConfig.ed == .valid && signatureConfig.dsa != .invalidFormat)
#else
            testPrevalidation(bundle: .edOnly, signatures: signatureConfig, expectedResult: signatureConfig.ed == .valid)
#endif
#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
            testPrevalidation(bundle: .both, signatures: signatureConfig, expectedResult: signatureConfig.ed == .valid && signatureConfig.dsa != .invalidFormat)
#else
            testPrevalidation(bundle: .both, signatures: signatureConfig, expectedResult: signatureConfig.ed == .valid)
#endif
        }
    }

    func testPostValidation(oldBundle oldBundleConfig: BundleConfig, newBundle newBundleConfig: BundleConfig, signatures signatureConfig: SignatureConfig, expectedResult: Bool, line: UInt = #line) {
        let oldBundle = self.bundle(oldBundleConfig)
        let host = SUHost(bundle: oldBundle)
        let signatures = self.signatures(signatureConfig)

        let validator = SUUpdateValidator(downloadPath: self.signedTestFilePath, signatures: signatures, host: host, verifierInformation: nil)

        let updateDirectory = temporaryDirectory("SUUpdateValidatorTest")!
        defer { try! FileManager.default.removeItem(atPath: updateDirectory) }
        let newBundle = self.bundle(newBundleConfig)
        try! FileManager.default.copyItem(at: newBundle.bundleURL, to: URL(fileURLWithPath: updateDirectory).appendingPathComponent(oldBundle.bundleURL.lastPathComponent))

        let result = (try? validator.validate(withUpdateDirectory: updateDirectory)) != nil
        XCTAssertEqual(result, expectedResult, "oldBundle: \(oldBundleConfig), newBundle: \(newBundleConfig), signatures: \(signatureConfig)", line: line)
    }

    func testPostValidation(bundle bundleConfig: BundleConfig, signatures signatureConfig: SignatureConfig, expectedResult: Bool, line: UInt = #line) {
        testPostValidation(oldBundle: bundleConfig, newBundle: bundleConfig, signatures: signatureConfig, expectedResult: expectedResult, line: line)
    }

    func testPostValidationWithoutCodeSigning() {
        for signatureConfig in SignatureConfig.allCases {
            testPostValidation(bundle: .none, signatures: signatureConfig, expectedResult: false)
#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
            testPostValidation(bundle: .dsaOnly, signatures: signatureConfig, expectedResult: signatureConfig.dsa == .valid)
#endif
#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
            testPostValidation(bundle: .edOnly, signatures: signatureConfig, expectedResult: signatureConfig.ed == .valid && signatureConfig.dsa != .invalidFormat)
#else
            testPostValidation(bundle: .edOnly, signatures: signatureConfig, expectedResult: signatureConfig.ed == .valid)
#endif
#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
            testPostValidation(bundle: .both, signatures: signatureConfig, expectedResult: signatureConfig.ed == .valid && signatureConfig.dsa != .invalidFormat)
#else
            testPostValidation(bundle: .both, signatures: signatureConfig, expectedResult: signatureConfig.ed == .valid)
#endif
        }
    }

    func testPostValidationWithCodeSigning() {
        for signatureConfig in SignatureConfig.allCases {
            testPostValidation(bundle: .codeSignedOnly, signatures: signatureConfig, expectedResult: true)
#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
            testPostValidation(bundle: .codeSignedBoth, signatures: signatureConfig, expectedResult: signatureConfig.ed == .valid && signatureConfig.dsa != .invalidFormat)
#else
            testPostValidation(bundle: .codeSignedBoth, signatures: signatureConfig, expectedResult: signatureConfig.ed == .valid)
#endif

            testPostValidation(bundle: .codeSignedInvalidOnly, signatures: signatureConfig, expectedResult: false)
            testPostValidation(bundle: .codeSignedInvalid, signatures: signatureConfig, expectedResult: false)
        }
    }

    func testPostValidationWithKeyRemoval() {
        for bundleConfig in BundleConfig.allCases {
#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
            testPostValidation(oldBundle: .dsaOnly, newBundle: bundleConfig, signatures: SignatureConfig(ed: .valid, dsa: .valid), expectedResult: bundleConfig.hasAnyKeys && bundleConfig != .codeSignedInvalid)
#else
            testPostValidation(oldBundle: .dsaOnly, newBundle: bundleConfig, signatures: SignatureConfig(ed: .valid), expectedResult: false)
#endif
            do {
#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
                let signatureConfig = SignatureConfig(ed: .valid, dsa: .valid)
#else
                let signatureConfig = SignatureConfig(ed: .valid)
#endif
                testPostValidation(oldBundle: .edOnly, newBundle: bundleConfig, signatures: signatureConfig, expectedResult: bundleConfig.hasAnyKeys && bundleConfig != .codeSignedInvalid)
            }
#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
            testPostValidation(oldBundle: .both, newBundle: bundleConfig, signatures: SignatureConfig(ed: .valid, dsa: .valid), expectedResult: bundleConfig.hasAnyKeys && bundleConfig != .codeSignedInvalid)
#else
            testPostValidation(oldBundle: .both, newBundle: bundleConfig, signatures: SignatureConfig(ed: .valid), expectedResult: bundleConfig.hasAnyKeys && bundleConfig != .codeSignedInvalid)
#endif
            do {
#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
                let signatureConfig = SignatureConfig(ed: .valid, dsa: .valid)
#else
                let signatureConfig = SignatureConfig(ed: .valid)
#endif
                testPostValidation(oldBundle: .codeSignedBoth, newBundle: bundleConfig, signatures: signatureConfig, expectedResult: bundleConfig.hasAnyKeys && bundleConfig.isValidCodeSigned)
            }
        }
    }

    func testPostValidationWithKeyRotation() {
        for signatureConfig in SignatureConfig.allCases {
#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
            let signatureIsValid = (signatureConfig.ed == .valid && signatureConfig.dsa != .invalidFormat)
#else
            let signatureIsValid = (signatureConfig.ed == .valid)
#endif

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

            // You can't remove code signing.
            testPostValidation(oldBundle: .codeSignedBoth, newBundle: .both, signatures: signatureConfig, expectedResult: false)
        }
    }
}
