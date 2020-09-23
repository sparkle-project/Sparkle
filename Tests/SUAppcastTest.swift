//
//  SUAppcastTest.swift
//  Sparkle
//
//  Created by Kornel on 17/02/2016.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

import XCTest
import Sparkle

class SUAppcastTest: XCTestCase {

    func testParseAppcast() {
        let appcast = SUAppcast()
        let testFile = Bundle(for: SUAppcastTest.self).path(forResource: "testappcast", ofType: "xml")!
        let testData = NSData(contentsOfFile: testFile)!

        do {
            let items = try appcast.parseAppcastItems(fromXMLData: testData as Data, relativeTo: nil) as! [SUAppcastItem]

            XCTAssertEqual(4, items.count)

            XCTAssertEqual("Version 2.0", items[0].title)
            XCTAssertEqual("desc", items[0].itemDescription)
            XCTAssertEqual("Sat, 26 Jul 2014 15:20:11 +0000", items[0].dateString)
            XCTAssertTrue(items[0].isCriticalUpdate)

            // This is the best release matching our system version
            XCTAssertEqual("Version 3.0", items[1].title)
            XCTAssertNil(items[1].itemDescription)
            XCTAssertNil(items[1].dateString)
            XCTAssertFalse(items[1].isCriticalUpdate)

            XCTAssertEqual("Version 4.0", items[2].title)
            XCTAssertNil(items[2].itemDescription)
            XCTAssertEqual("Sat, 26 Jul 2014 15:20:13 +0000", items[2].dateString)
            XCTAssertFalse(items[2].isCriticalUpdate)

            XCTAssertEqual("Version 5.0", items[3].title)
            XCTAssertNil(items[3].itemDescription)
            XCTAssertNil(items[3].dateString)
            XCTAssertFalse(items[3].isCriticalUpdate)

            // Test best appcast item & a delta update item
            var deltaItem: SUAppcastItem?
            let bestAppcastItem = SUAppcastDriver.bestItem(fromAppcastItems: items, getDeltaItem: &deltaItem, withHostVersion: "1.0", comparator: SUStandardVersionComparator())

            XCTAssertEqual(bestAppcastItem, items[1])
            XCTAssertEqual(deltaItem!.fileURL.lastPathComponent, "3.0_from_1.0.patch")

            // Test latest delta update item available
            var latestDeltaItem: SUAppcastItem?
            SUAppcastDriver.bestItem(fromAppcastItems: items, getDeltaItem: &latestDeltaItem, withHostVersion: "2.0", comparator: SUStandardVersionComparator())

            XCTAssertEqual(latestDeltaItem!.fileURL.lastPathComponent, "3.0_from_2.0.patch")

            // Test a delta item that does not exist
            var nonexistantDeltaItem: SUAppcastItem?
            SUAppcastDriver.bestItem(fromAppcastItems: items, getDeltaItem: &nonexistantDeltaItem, withHostVersion: "2.1", comparator: SUStandardVersionComparator())

            XCTAssertNil(nonexistantDeltaItem)
        } catch let err as NSError {
            NSLog("%@", err)
            XCTFail(err.localizedDescription)
        }
    }

    func testParseAppcastWithLocalizedReleaseNotes() {
        let appcast = SUAppcast()
        let testFile = Bundle(for: SUAppcastTest.self).path(forResource: "testlocalizedreleasenotesappcast",
                                                            ofType: "xml")!
        let testFileUrl = URL(fileURLWithPath: testFile)
        XCTAssertNotNil(testFileUrl)

         do {
            let testFileData = try Data(contentsOf: testFileUrl)
            let items = try appcast.parseAppcastItems(fromXMLData: testFileData, relativeTo: testFileUrl) as! [SUAppcastItem];
            XCTAssertEqual("https://sparkle-project.org/#localized_notes_link_works", items[0].releaseNotesURL.absoluteString)
        } catch let err as NSError {
            NSLog("%@", err)
            XCTFail(err.localizedDescription)
        }
    }

    func testNamespaces() {
        let appcast = SUAppcast()
        let testFile = Bundle(for: SUAppcastTest.self).path(forResource: "testnamespaces", ofType: "xml")!
        let testData = NSData(contentsOfFile: testFile)!

        do {
            let items = try appcast.parseAppcastItems(fromXMLData: testData as Data, relativeTo: nil) as! [SUAppcastItem]

            XCTAssertEqual(2, items.count)

            XCTAssertEqual("Version 2.0", items[1].title)
            XCTAssertEqual("desc", items[1].itemDescription)
            XCTAssertNotNil(items[0].releaseNotesURL)
            XCTAssertEqual("https://sparkle-project.org/#works", items[0].releaseNotesURL!.absoluteString)
        } catch let err as NSError {
            NSLog("%@", err)
            XCTFail(err.localizedDescription)
        }
    }

    func testRelativeURLs() {
        let appcast = SUAppcast()
        let testFile = Bundle(for: SUAppcastTest.self).path(forResource: "test-relative-urls", ofType: "xml")!
        let testData = NSData(contentsOfFile: testFile)!

        do {
            let baseURL = URL(string: "https://fake.sparkle-project.org/updates/index.xml")!
            let items = try appcast.parseAppcastItems(fromXMLData: testData as Data, relativeTo: baseURL) as! [SUAppcastItem]

            XCTAssertEqual(2, items.count)

            XCTAssertEqual("https://fake.sparkle-project.org/updates/release-3.0.zip", items[0].fileURL?.absoluteString)
            XCTAssertEqual("https://fake.sparkle-project.org/updates/notes/relnote-3.0.txt", items[0].releaseNotesURL?.absoluteString)

            XCTAssertEqual("https://fake.sparkle-project.org/info/info-2.0.txt", items[1].infoURL?.absoluteString)

        } catch let err as NSError {
            NSLog("%@", err)
            XCTFail(err.localizedDescription)
        }
    }

}
