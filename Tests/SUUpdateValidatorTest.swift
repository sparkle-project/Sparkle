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
    enum KeyConfig: String, CaseIterable, Equatable {
        case none = "None"
        case dsaOnly = "DSAOnly"
        case edOnly = "EDOnly"
        case both = "Both"
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

    func bundle(keys config: KeyConfig) -> Bundle {
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

    func testPrevalidation(keys keysConfig: KeyConfig, signatures signatureConfig: SignatureConfig, expectedResult: Bool, line: UInt = #line) {
        let host = SUHost(bundle: self.bundle(keys: keysConfig))!
        let signatures = self.signatures(signatureConfig)

        let validator = SUUpdateValidator(downloadPath: self.signedTestFilePath, signatures: signatures, host: host)

        let result = validator.validateDownloadPath()
        XCTAssertEqual(result, expectedResult, "keys: \(keysConfig), signatures: \(signatureConfig)", line: line)
    }

    func testPrevalidation() {
        for signatureConfig in SignatureConfig.allCases {
            testPrevalidation(keys: .none, signatures: signatureConfig, expectedResult: false)
            testPrevalidation(keys: .dsaOnly, signatures: signatureConfig, expectedResult: signatureConfig.dsa == .valid)
            testPrevalidation(keys: .edOnly, signatures: signatureConfig, expectedResult: signatureConfig.ed == .valid)
            testPrevalidation(keys: .both, signatures: signatureConfig, expectedResult: signatureConfig.dsa == .valid && signatureConfig.ed != .invalid)
        }
    }

    func testPostValidationWithoutCodeSigning(keys keysConfig: KeyConfig, signatures signatureConfig: SignatureConfig, expectedResult: Bool, line: UInt = #line) {
        let bundle = self.bundle(keys: keysConfig)
        let host = SUHost(bundle: bundle)!
        let signatures = self.signatures(signatureConfig)

        let validator = SUUpdateValidator(downloadPath: self.signedTestFilePath, signatures: signatures, host: host)

        let result = validator.validate(withUpdateDirectory: bundle.bundleURL.deletingLastPathComponent().path)
        XCTAssertEqual(result, expectedResult, "keys: \(keysConfig), signatures: \(signatureConfig)", line: line)
    }

    func testPostValidationWithoutCodeSigning() {
        for signatureConfig in SignatureConfig.allCases {
            testPostValidationWithoutCodeSigning(keys: .none, signatures: signatureConfig, expectedResult: false)
            testPostValidationWithoutCodeSigning(keys: .dsaOnly, signatures: signatureConfig, expectedResult: signatureConfig.dsa == .valid)
            testPostValidationWithoutCodeSigning(keys: .edOnly, signatures: signatureConfig, expectedResult: signatureConfig.ed == .valid)
            testPostValidationWithoutCodeSigning(keys: .both, signatures: signatureConfig, expectedResult: signatureConfig.dsa == .valid && signatureConfig.ed != .invalid)
        }
    }
}
