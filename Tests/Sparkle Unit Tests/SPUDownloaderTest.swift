//
//  SPUDownloaderTest.swift
//  Sparkle
//
//  Created by Deadpikle on 12/28/17.
//  Copyright © 2017 Sparkle Project. All rights reserved.
//

import XCTest
import Sparkle

class SPUDownloaderTestDelegate: NSObject, SPUDownloaderDelegate {

    var asyncExpectation: XCTestExpectation?
    var tempResult: SPUDownloadData?
    var downloadPath: URL?

    func downloaderDidReceiveData(ofLength length: UInt64)
    {
    }

    func downloaderDidReceiveExpectedContentLength(_ expectedContentLength: Int64)
    {
    }

    func downloaderDidSetDestinationName(_ destinationName: String, temporaryDirectory: String)
    {
        self.downloadPath = NSURL(fileURLWithPath: temporaryDirectory).appendingPathComponent(destinationName)
    }

    func downloaderDidFailWithError(_ error: Error)
    {
        XCTFail(error.localizedDescription)
        self.asyncExpectation?.fulfill()
    }

    func downloaderDidFinish(withTemporaryDownloadData downloadData: SPUDownloadData?)
    {
        self.tempResult = downloadData
        self.asyncExpectation?.fulfill()
    }
}

class SPUDownloaderTest: XCTestCase
{
    func performTemporaryDownloadTest(withDownloader downloader: SPUDownloader, delegate: SPUDownloaderTestDelegate)
    {
        let delegateExpectation = expectation(description: "SPUDownloader temporary download")
        delegate.asyncExpectation = delegateExpectation

        let url = URL.init(string: "https://sparkle-project.org/unit_test/test.xml")
        var request = URLRequest(url: url!, cachePolicy: .reloadIgnoringCacheData, timeoutInterval: 30.0)
        request.setValue("application/rss+xml,*/*;q=0.1", forHTTPHeaderField: "Accept")

        let downloaderRequest = SPUURLRequest(request: request as URLRequest)
        downloader.startTemporaryDownload(with: downloaderRequest)

        super.waitForExpectations(timeout: 30.0) { error in
            if let error = error {
                XCTFail("waitForExpectations had error: \(error)")
            }

            guard let result = delegate.tempResult else {
                XCTFail("Expected result to be non-nil")
                return
            }

            let str = String.init(data: result.data,
                                  encoding: String.Encoding(rawValue: String.Encoding.utf8.rawValue))
            XCTAssert(str == "<test>appcast</test>\n")
        }
    }

    // SHA256 code from: https://stackoverflow.com/a/42934185/3938401
    func sha256(data: Data) -> Data
    {
        var digestData = Data(count: Int(CC_SHA256_DIGEST_LENGTH))

        _ = digestData.withUnsafeMutableBytes {digestBytes in
            data.withUnsafeBytes {messageBytes in
                CC_SHA256(messageBytes, CC_LONG(data.count), digestBytes)
            }
        }
        return digestData
    }

    func performPersistentDownloadTest(withDownloader downloader: SPUDownloader, delegate: SPUDownloaderTestDelegate)
    {
        let delegateExpectation = expectation(description: "SPUDownloader persistent download")
        delegate.asyncExpectation = delegateExpectation

        let url = URL.init(string: "https://sparkle-project.org/unit_test/icon.png")
        var request = URLRequest(url: url!, cachePolicy: .reloadIgnoringCacheData, timeoutInterval: 30.0)
        request.setValue("image/png", forHTTPHeaderField: "Accept")

        let downloaderRequest = SPUURLRequest(request: request as URLRequest)
        let bundleIdentifier = Bundle.init(for: self.superclass!).bundleIdentifier
        downloader.startPersistentDownload(with: downloaderRequest, bundleIdentifier: bundleIdentifier!, desiredFilename: "icon")

        super.waitForExpectations(timeout: 30.0) { error in
            if let error = error {
                XCTFail("waitForExpectations had error: \(error)")
            }

            guard let filePath = delegate.downloadPath else {
                XCTFail("Expected download path to be non-nil")
                return
            }

            let fileManager = FileManager.default
            XCTAssert(fileManager.fileExists(atPath: filePath.path))

            do {
                let iconData = try Data.init(contentsOf: filePath)
                let sha256HashData = self.sha256(data: iconData)
                let hashString = sha256HashData.map { String(format: "%02hhx", $0) }.joined().uppercased()

                XCTAssert(hashString == "F262E65663C505B9C6449B61660FA3F223912465AE637014288294A8CB286B85")
            } catch {
                XCTFail("Something went wrong reading the file data")
            }
        }
    }

    func testDeprecatedDownloader()
    {
        let delegate = SPUDownloaderTestDelegate()
        var downloader = SPUDownloaderDeprecated(delegate: delegate)

        self.performTemporaryDownloadTest(withDownloader: downloader!, delegate: delegate)
        downloader = SPUDownloaderDeprecated(delegate: delegate)
        self.performPersistentDownloadTest(withDownloader: downloader!, delegate: delegate)
    }

    func testSessionDownloader()
    {
        let delegate = SPUDownloaderTestDelegate()
        var downloader = SPUDownloaderSession(delegate: delegate)

        self.performTemporaryDownloadTest(withDownloader: downloader!, delegate: delegate)
        downloader = SPUDownloaderSession(delegate: delegate)
        self.performPersistentDownloadTest(withDownloader: downloader!, delegate: delegate)
    }
}
