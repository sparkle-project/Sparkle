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
        let testURL = Bundle(for: SUAppcastTest.self).url(forResource: "testappcast", withExtension: "xml")!
        
        do {
            let testData = try Data(contentsOf: testURL)
            
            let appcast = try SUAppcast(xmlData: testData, relativeTo: nil)
            let items = appcast.items

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
            XCTAssertEqual(items[1].phasedRolloutInterval, 86400)

            XCTAssertEqual("Version 4.0", items[2].title)
            XCTAssertNil(items[2].itemDescription)
            XCTAssertEqual("Sat, 26 Jul 2014 15:20:13 +0000", items[2].dateString)
            XCTAssertFalse(items[2].isCriticalUpdate)

            XCTAssertEqual("Version 5.0", items[3].title)
            XCTAssertNil(items[3].itemDescription)
            XCTAssertNil(items[3].dateString)
            XCTAssertFalse(items[3].isCriticalUpdate)

            // Test best appcast item & a delta update item
            let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: nil, skippedUpdate: nil, hostVersion: nil, versionComparator: nil, testOSVersion: true, testMinimumAutoupdateVersion: false)
            
            let supportedAppcastItems = supportedAppcast.items
            
            var deltaItem: SUAppcastItem?
            let bestAppcastItem = SUAppcastDriver.bestItem(fromAppcastItems: supportedAppcastItems, getDeltaItem: &deltaItem, withHostVersion: "1.0", comparator: SUStandardVersionComparator())

            XCTAssertEqual(bestAppcastItem, items[1])
            XCTAssertEqual(deltaItem!.fileURL!.lastPathComponent, "3.0_from_1.0.patch")

            // Test latest delta update item available
            var latestDeltaItem: SUAppcastItem?
            SUAppcastDriver.bestItem(fromAppcastItems: supportedAppcastItems, getDeltaItem: &latestDeltaItem, withHostVersion: "2.0", comparator: SUStandardVersionComparator())

            XCTAssertEqual(latestDeltaItem!.fileURL!.lastPathComponent, "3.0_from_2.0.patch")

            // Test a delta item that does not exist
            var nonexistantDeltaItem: SUAppcastItem?
            SUAppcastDriver.bestItem(fromAppcastItems: supportedAppcastItems, getDeltaItem: &nonexistantDeltaItem, withHostVersion: "2.1", comparator: SUStandardVersionComparator())

            XCTAssertNil(nonexistantDeltaItem)
        } catch let err as NSError {
            NSLog("%@", err)
            XCTFail(err.localizedDescription)
        }
    }
    
    func testMinimumAutoupdateVersion() {
        let testURL = Bundle(for: SUAppcastTest.self).url(forResource: "testappcast_minimumAutoupdateVersion", withExtension: "xml")!
        
        do {
            let testData = try Data(contentsOf: testURL)
            
            let appcast = try SUAppcast(xmlData: testData, relativeTo: nil)
            
            XCTAssertEqual(2, appcast.items.count)
            
            let versionComparator = SUStandardVersionComparator()
            
            // Because 3.0 has minimum autoupdate version of 2.0, we should be offered 2.0
            do {
                let hostVersion = "1.0"
                
                let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: nil, skippedUpdate: nil, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: true)
                
                XCTAssertEqual(1, supportedAppcast.items.count)
                
                let bestAppcastItem = SUAppcastDriver.bestItem(fromAppcastItems: supportedAppcast.items, getDeltaItem: nil, withHostVersion: hostVersion, comparator: versionComparator)
                
                XCTAssertEqual(bestAppcastItem.versionString, "2.0")
            }
            
            // We should be offered 3.0 if host version is 2.0
            do {
                let hostVersion = "2.0"
                
                let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: nil, skippedUpdate: nil, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: true)
                
                XCTAssertEqual(2, supportedAppcast.items.count)
                
                let bestAppcastItem = SUAppcastDriver.bestItem(fromAppcastItems: supportedAppcast.items, getDeltaItem: nil, withHostVersion: hostVersion, comparator: versionComparator)
                
                XCTAssertEqual(bestAppcastItem.versionString, "3.0")
            }
            
            // We should be offered 3.0 if host version is 2.5
            do {
                let hostVersion = "2.5"
                
                let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: nil, skippedUpdate: nil, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: true)
                
                XCTAssertEqual(2, supportedAppcast.items.count)
                
                let bestAppcastItem = SUAppcastDriver.bestItem(fromAppcastItems: supportedAppcast.items, getDeltaItem: nil, withHostVersion: hostVersion, comparator: versionComparator)
                
                XCTAssertEqual(bestAppcastItem.versionString, "3.0")
            }
            
            // Because 3.0 has minimum autoupdate version of 2.0, we would be be offered 2.0, but not if it has been skipped
            do {
                let hostVersion = "1.0"
                
                // There should be no items if 2.0 is skipped from 1.0 and 3.0 fails minimum autoupdate version
                do {
                    let skippedUpdate = SPUSkippedUpdate(minorVersion: "2.0", majorVersion: nil)
                    
                    let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: nil, skippedUpdate: skippedUpdate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: true)
                
                    XCTAssertEqual(0, supportedAppcast.items.count)
                }
                
                // Try again but allowing minimum autoupdate version to fail
                do {
                    let skippedUpdate = SPUSkippedUpdate(minorVersion: "2.0", majorVersion: nil)
                    
                    let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: nil, skippedUpdate: skippedUpdate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: false)
                
                    XCTAssertEqual(1, supportedAppcast.items.count)
                    
                    let bestAppcastItem = SUAppcastDriver.bestItem(fromAppcastItems: supportedAppcast.items, getDeltaItem: nil, withHostVersion: hostVersion, comparator: versionComparator)
                    
                    XCTAssertEqual(bestAppcastItem.versionString, "3.0")
                }
                
                // Allow minimum autoupdate version to fail and only skip 3.0
                do {
                    let skippedUpdate = SPUSkippedUpdate(minorVersion: nil, majorVersion: "3.0")
                    
                    let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: nil, skippedUpdate: skippedUpdate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: false)
                
                    XCTAssertEqual(1, supportedAppcast.items.count)
                    
                    let bestAppcastItem = SUAppcastDriver.bestItem(fromAppcastItems: supportedAppcast.items, getDeltaItem: nil, withHostVersion: hostVersion, comparator: versionComparator)
                    
                    XCTAssertEqual(bestAppcastItem.versionString, "2.0")
                }
                
                // Allow minimum autoupdate version to fail skipping both 2.0 and 3.0
                do {
                    let skippedUpdate = SPUSkippedUpdate(minorVersion: "2.0", majorVersion: "3.0")
                    
                    let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: nil, skippedUpdate: skippedUpdate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: false)
                
                    XCTAssertEqual(0, supportedAppcast.items.count)
                }
                
                // Allow minimum autoupdate version to fail and only skip "2.5"
                // This should implicitly only skip 2.0
                do {
                    let skippedUpdate = SPUSkippedUpdate(minorVersion: "2.5", majorVersion: nil)
                    
                    let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: nil, skippedUpdate: skippedUpdate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: false)
                
                    XCTAssertEqual(1, supportedAppcast.items.count)
                    
                    let bestAppcastItem = SUAppcastDriver.bestItem(fromAppcastItems: supportedAppcast.items, getDeltaItem: nil, withHostVersion: hostVersion, comparator: versionComparator)
                    
                    XCTAssertEqual(bestAppcastItem.versionString, "3.0")
                }
                
                // This should not skip anything but require passing minimum autoupdate version
                do {
                    let skippedUpdate = SPUSkippedUpdate(minorVersion: "1.5", majorVersion: nil)
                    
                    let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: nil, skippedUpdate: skippedUpdate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: true)
                
                    XCTAssertEqual(1, supportedAppcast.items.count)
                    
                    let bestAppcastItem = SUAppcastDriver.bestItem(fromAppcastItems: supportedAppcast.items, getDeltaItem: nil, withHostVersion: hostVersion, comparator: versionComparator)
                    
                    XCTAssertEqual(bestAppcastItem.versionString, "2.0")
                }
                
                // This should not skip anything but allow failing minimum autoupdate version
                do {
                    let skippedUpdate = SPUSkippedUpdate(minorVersion: "1.5", majorVersion: nil)
                    
                    let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: nil, skippedUpdate: skippedUpdate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: false)
                
                    XCTAssertEqual(2, supportedAppcast.items.count)
                    
                    let bestAppcastItem = SUAppcastDriver.bestItem(fromAppcastItems: supportedAppcast.items, getDeltaItem: nil, withHostVersion: hostVersion, comparator: versionComparator)
                    
                    XCTAssertEqual(bestAppcastItem.versionString, "3.0")
                }
                
                // This should not skip anything but require passing minimum autoupdate version
                do {
                    let skippedUpdate = SPUSkippedUpdate(minorVersion: "1.5", majorVersion: "1.0")
                    
                    let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: nil, skippedUpdate: skippedUpdate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: true)
                
                    XCTAssertEqual(1, supportedAppcast.items.count)
                    
                    let bestAppcastItem = SUAppcastDriver.bestItem(fromAppcastItems: supportedAppcast.items, getDeltaItem: nil, withHostVersion: hostVersion, comparator: versionComparator)
                    
                    XCTAssertEqual(bestAppcastItem.versionString, "2.0")
                }
                
                // This should not skip anything but allow failing minimum autoupdate version
                do {
                    let skippedUpdate = SPUSkippedUpdate(minorVersion: "1.5", majorVersion: "1.0")
                    
                    let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: nil, skippedUpdate: skippedUpdate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: false)
                
                    XCTAssertEqual(2, supportedAppcast.items.count)
                    
                    let bestAppcastItem = SUAppcastDriver.bestItem(fromAppcastItems: supportedAppcast.items, getDeltaItem: nil, withHostVersion: hostVersion, comparator: versionComparator)
                    
                    XCTAssertEqual(bestAppcastItem.versionString, "3.0")
                }
            }
        } catch let err as NSError {
            NSLog("%@", err)
            XCTFail(err.localizedDescription)
        }
    }

    func testParseAppcastWithLocalizedReleaseNotes() {
        let testFile = Bundle(for: SUAppcastTest.self).path(forResource: "testlocalizedreleasenotesappcast",
                                                            ofType: "xml")!
        let testFileUrl = URL(fileURLWithPath: testFile)
        XCTAssertNotNil(testFileUrl)

         do {
            let testFileData = try Data(contentsOf: testFileUrl)
            let appcast = try SUAppcast(xmlData: testFileData, relativeTo: testFileUrl)
            let items = appcast.items
            XCTAssertEqual("https://sparkle-project.org/#localized_notes_link_works", items[0].releaseNotesURL!.absoluteString)
        } catch let err as NSError {
            NSLog("%@", err)
            XCTFail(err.localizedDescription)
        }
    }

    func testNamespaces() {
        let testFile = Bundle(for: SUAppcastTest.self).path(forResource: "testnamespaces", ofType: "xml")!
        let testData = NSData(contentsOfFile: testFile)!

        do {
            let appcast = try SUAppcast(xmlData: testData as Data, relativeTo: nil)
            let items = appcast.items

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
        let testFile = Bundle(for: SUAppcastTest.self).path(forResource: "test-relative-urls", ofType: "xml")!
        let testData = NSData(contentsOfFile: testFile)!

        do {
            let baseURL = URL(string: "https://fake.sparkle-project.org/updates/index.xml")!
            
            let appcast = try SUAppcast(xmlData: testData as Data, relativeTo: baseURL)
            let items = appcast.items

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
