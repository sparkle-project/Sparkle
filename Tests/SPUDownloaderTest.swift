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
    
    func downloaderDidFailWithError(_ error: Error)
    {
        XCTFail(error.localizedDescription);
        asyncExpectation?.fulfill()
    }
    
    func downloaderDidReceiveData(ofLength length: UInt64)
    {
        
    }
    
    func downloaderDidReceiveExpectedContentLength(_ expectedContentLength: Int64)
    {
        
    }
    
    func downloaderDidFinish(withTemporaryDownloadData downloadData: SPUDownloadData?)
    {
        XCTAssert(downloadData != nil)
        let str = String.init(data: downloadData!.data, encoding: String.Encoding(rawValue: String.Encoding.utf8.rawValue))
        XCTAssert(str == "<test>appcast</test>\n")
        asyncExpectation?.fulfill()
    }
    
    func downloaderDidSetDestinationName(_ destinationName: String, temporaryDirectory: String)
    {
        
    }
}

class SPUDownloaderTest: XCTestCase
{
    func performTemporaryDownloadTest(withDownloader downloader: SPUDownloader, delegate: SPUDownloaderTestDelegate)
    {
        let delegateExpectation = expectation(description: "SPUDownloaderDeprecated temporary download")
        delegate.asyncExpectation = delegateExpectation
        
        let url = URL.init(string: "https://sparkle-project.org/unit_test/test.xml")
        var request = URLRequest(url: url!, cachePolicy: .reloadIgnoringCacheData, timeoutInterval: 30.0)
        request.setValue("application/rss+xml,*/*;q=0.1", forHTTPHeaderField: "Accept")
        
        let downloaderRequest = SPUURLRequest(request: request as URLRequest)
        downloader.startTemporaryDownload(with: downloaderRequest)
        
        super.waitForExpectations(timeout: 30.0, handler: nil)
    }
    
    func testDeprecatedDownloader()
    {
        let delegate = SPUDownloaderTestDelegate()
        let downloader = SPUDownloaderDeprecated(delegate: delegate)
        
        self.performTemporaryDownloadTest(withDownloader: downloader!, delegate: delegate)
    }
    
    func testSessionDownloader()
    {
        let delegate = SPUDownloaderTestDelegate()
        let downloader = SPUDownloaderSession(delegate: delegate)
        
        self.performTemporaryDownloadTest(withDownloader: downloader!, delegate: delegate)
    }
}
