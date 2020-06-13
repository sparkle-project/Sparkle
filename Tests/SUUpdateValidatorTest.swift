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
    enum SigningConfig: String {
        case none = "None"
        case dsaOnly = "DSAOnly"
        case edOnly = "EDOnly"
        case both = "Both"
    }

    func host(keys config: SigningConfig) -> SUHost {
        let testBundle = Bundle(for: SUUpdateValidatorTest.self)
        let configBundleURL = testBundle.url(forResource: config.rawValue, withExtension: "bundle", subdirectory: "SUUpdateValidatorTest")!
        return SUHost(bundle: Bundle(url: configBundleURL)!)
    }

    func signatures(_ config: SigningConfig) -> SUSignatures {
        let dsaSig = "MCwCFCIHCIYYkfZavNzTitTW5tlRp/k5AhQ40poFytqcVhIYdCxQznaXeJPJDQ=="
        let edSig = "EIawm2YkDZ2gBfkEMF2+1VuuTeXnCGZOdnMdVgPPvDZioq7bvDayXqKkIIzSjKMmeFdcFJOHdnba5ZV60+gPBw=="
        switch config {
        case .none: return SUSignatures(dsa: nil, ed: nil)
        case .dsaOnly: return SUSignatures(dsa: dsaSig, ed: nil)
        case .edOnly: return SUSignatures(dsa: nil, ed: edSig)
        case .both: return SUSignatures(dsa: dsaSig, ed: edSig)
        }
    }

    var signedTestFilePath: String {
        let testBundle = Bundle(for: SUUpdateValidatorTest.self)
        return testBundle.path(forResource: "signed-test-file", ofType: "txt")!
    }

    func testPrevalidation(keys keysConfig: SigningConfig, signatures signatureConfig: SigningConfig, expectedResult: Bool, line: UInt = #line) {
        let host = self.host(keys: keysConfig)
        let signatures = self.signatures(signatureConfig)

        let validator = SUUpdateValidator(downloadPath: self.signedTestFilePath, signatures: signatures, host: host)

        let result = validator.validateDownloadPath()
        XCTAssertEqual(result, expectedResult, line: line)
    }

    func testPrevalidation() {
        testPrevalidation(keys: .none, signatures: .none, expectedResult: false)
        testPrevalidation(keys: .none, signatures: .dsaOnly, expectedResult: false)
        testPrevalidation(keys: .none, signatures: .edOnly, expectedResult: false)
        testPrevalidation(keys: .none, signatures: .both, expectedResult: false)

        testPrevalidation(keys: .dsaOnly, signatures: .none, expectedResult: false)
        testPrevalidation(keys: .dsaOnly, signatures: .dsaOnly, expectedResult: true)
        testPrevalidation(keys: .dsaOnly, signatures: .edOnly, expectedResult: false)
        testPrevalidation(keys: .dsaOnly, signatures: .both, expectedResult: true)

        testPrevalidation(keys: .edOnly, signatures: .none, expectedResult: false)
        testPrevalidation(keys: .edOnly, signatures: .dsaOnly, expectedResult: false)
        testPrevalidation(keys: .edOnly, signatures: .edOnly, expectedResult: true)
        testPrevalidation(keys: .edOnly, signatures: .both, expectedResult: true)

        testPrevalidation(keys: .both, signatures: .none, expectedResult: false)
        testPrevalidation(keys: .both, signatures: .dsaOnly, expectedResult: true)
        testPrevalidation(keys: .both, signatures: .edOnly, expectedResult: false)
        testPrevalidation(keys: .both, signatures: .both, expectedResult: true)
    }
}
