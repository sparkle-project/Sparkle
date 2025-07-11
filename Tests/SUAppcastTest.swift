//
//  SUAppcastTest.swift
//  Sparkle
//
//  Created by Kornel on 17/02/2016.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

import XCTest

class SUAppcastTest: XCTestCase {

    func testParseAppcast() {
        let testURL = Bundle(for: SUAppcastTest.self).url(forResource: "testappcast", withExtension: "xml")!
        
        do {
            let testData = try Data(contentsOf: testURL)
            
            let versionComparator = SUStandardVersionComparator.default
            let hostVersion = "1.0"
            let stateResolver = SPUAppcastItemStateResolver(hostVersion: hostVersion, applicationVersionComparator: versionComparator, standardVersionComparator: versionComparator)
            
            let appcast = try SUAppcast(xmlData: testData, relativeTo: nil, stateResolver: stateResolver)
            let items = appcast.items

            XCTAssertEqual(4, items.count)

            XCTAssertEqual("Version 2.0", items[0].title)
            XCTAssertEqual("desc", items[0].itemDescription)
            XCTAssertEqual("plain-text", items[0].itemDescriptionFormat)
            XCTAssertEqual("Sat, 26 Jul 2014 15:20:11 +0000", items[0].dateString)
            XCTAssertTrue(items[0].isCriticalUpdate)
            XCTAssertEqual(items[0].versionString, "2.0")

            // This is the best release matching our system version
            XCTAssertEqual("Version 3.0", items[1].title)
            XCTAssertEqual("desc3", items[1].itemDescription)
            XCTAssertEqual("html", items[1].itemDescriptionFormat)
            XCTAssertNil(items[1].dateString)
            XCTAssertTrue(items[1].isCriticalUpdate)
            XCTAssertEqual(items[1].phasedRolloutInterval, 86400)
            XCTAssertEqual(items[1].versionString, "3.0")

            XCTAssertEqual("Version 4.0", items[2].title)
            XCTAssertNil(items[2].itemDescription)
            XCTAssertEqual("Sat, 26 Jul 2014 15:20:13 +0000", items[2].dateString)
            XCTAssertFalse(items[2].isCriticalUpdate)

            XCTAssertEqual("Version 5.0", items[3].title)
            XCTAssertNil(items[3].itemDescription)
            XCTAssertNil(items[3].dateString)
            XCTAssertFalse(items[3].isCriticalUpdate)

            // Test best appcast item & a delta update item
            let currentDate = Date()
            let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: nil, skippedUpdate: nil, currentDate: currentDate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: false)
            
            let supportedAppcastItems = supportedAppcast.items
            
            var deltaItem: SUAppcastItem?
            let bestAppcastItem = SUAppcastDriver.bestItem(fromAppcastItems: supportedAppcastItems, getDeltaItem: &deltaItem, withHostVersion: "1.0", comparator: SUStandardVersionComparator())

            XCTAssertEqual(bestAppcastItem, items[1])
            XCTAssertEqual(deltaItem!.fileURL!.lastPathComponent, "3.0_from_1.0.patch")
            XCTAssertEqual(deltaItem!.versionString, "3.0")

            // Test latest delta update item available
            var latestDeltaItem: SUAppcastItem?
            SUAppcastDriver.bestItem(fromAppcastItems: supportedAppcastItems, getDeltaItem: &latestDeltaItem, withHostVersion: "2.0", comparator: SUStandardVersionComparator())

            XCTAssertEqual(latestDeltaItem!.fileURL!.lastPathComponent, "3.0_from_2.0.patch")

            // Test a delta item that does not exist
            var nonexistentDeltaItem: SUAppcastItem?
            SUAppcastDriver.bestItem(fromAppcastItems: supportedAppcastItems, getDeltaItem: &nonexistentDeltaItem, withHostVersion: "2.1", comparator: SUStandardVersionComparator())

            XCTAssertNil(nonexistentDeltaItem)
        } catch let err as NSError {
            NSLog("%@", err)
            XCTFail(err.localizedDescription)
        }
    }
    
    func testChannelsAndMacOSReleases() {
        let testURL = Bundle(for: SUAppcastTest.self).url(forResource: "testappcast_channels", withExtension: "xml")!
        
        do {
            let testData = try Data(contentsOf: testURL)
            
            let versionComparator = SUStandardVersionComparator.default
            let hostVersion = "1.0"
            let stateResolver = SPUAppcastItemStateResolver(hostVersion: hostVersion, applicationVersionComparator: versionComparator, standardVersionComparator: versionComparator)
            
            let appcast = try SUAppcast(xmlData: testData, relativeTo: nil, stateResolver: stateResolver)
            XCTAssertEqual(6, appcast.items.count)
            
            do {
                let filteredAppcast = SUAppcastDriver.filterAppcast(appcast, forMacOSAndAllowedChannels: ["beta", "nightly"])
                XCTAssertEqual(4, filteredAppcast.items.count)
                
                XCTAssertEqual("2.0", filteredAppcast.items[0].versionString)
                XCTAssertEqual("3.0", filteredAppcast.items[1].versionString)
                XCTAssertEqual("4.0", filteredAppcast.items[2].versionString)
                XCTAssertEqual("5.0", filteredAppcast.items[3].versionString)
            }
            
            do {
                let filteredAppcast = SUAppcastDriver.filterAppcast(appcast, forMacOSAndAllowedChannels: [])
                XCTAssertEqual(2, filteredAppcast.items.count)
                XCTAssertEqual("2.0", filteredAppcast.items[0].versionString)
                XCTAssertEqual("3.0", filteredAppcast.items[1].versionString)
            }
            
            do {
                let filteredAppcast = SUAppcastDriver.filterAppcast(appcast, forMacOSAndAllowedChannels: ["beta"])
                XCTAssertEqual(3, filteredAppcast.items.count)
                XCTAssertEqual("2.0", filteredAppcast.items[0].versionString)
                XCTAssertEqual("3.0", filteredAppcast.items[1].versionString)
                XCTAssertEqual("4.0", filteredAppcast.items[2].versionString)
            }
            
            do {
                let filteredAppcast = SUAppcastDriver.filterAppcast(appcast, forMacOSAndAllowedChannels: ["nightly"])
                XCTAssertEqual(3, filteredAppcast.items.count)
                XCTAssertEqual("2.0", filteredAppcast.items[0].versionString)
                XCTAssertEqual("3.0", filteredAppcast.items[1].versionString)
                XCTAssertEqual("5.0", filteredAppcast.items[2].versionString)
            }
            
            do {
                let filteredAppcast = SUAppcastDriver.filterAppcast(appcast, forMacOSAndAllowedChannels: ["madeup"])
                XCTAssertEqual("2.0", filteredAppcast.items[0].versionString)
                XCTAssertEqual("3.0", filteredAppcast.items[1].versionString)
                XCTAssertEqual(2, filteredAppcast.items.count)
            }
        } catch let err as NSError {
            NSLog("%@", err)
            XCTFail(err.localizedDescription)
        }
    }
    
    func testCriticalUpdateVersion() {
        let testURL = Bundle(for: SUAppcastTest.self).url(forResource: "testappcast", withExtension: "xml")!
        
        do {
            let testData = try Data(contentsOf: testURL)
            
            let versionComparator = SUStandardVersionComparator.default
            
            // If critical update version is 1.5 and host version is 1.0, update should be marked critical
            do {
                let hostVersion = "1.0"
                let stateResolver = SPUAppcastItemStateResolver(hostVersion: hostVersion, applicationVersionComparator: versionComparator, standardVersionComparator: versionComparator)
                
                let appcast = try SUAppcast(xmlData: testData, relativeTo: nil, stateResolver: stateResolver)
                XCTAssertTrue(appcast.items[0].isCriticalUpdate)
            }
            
            // If critical update version is 1.5 and host version is 1.5, update should not be marked critical
            do {
                let hostVersion = "1.5"
                let stateResolver = SPUAppcastItemStateResolver(hostVersion: hostVersion, applicationVersionComparator: versionComparator, standardVersionComparator: versionComparator)
                
                let appcast = try SUAppcast(xmlData: testData, relativeTo: nil, stateResolver: stateResolver)
                XCTAssertFalse(appcast.items[0].isCriticalUpdate)
            }
            
            // If critical update version is 1.5 and host version is 1.6, update should not be marked critical
            do {
                let hostVersion = "1.6"
                let stateResolver = SPUAppcastItemStateResolver(hostVersion: hostVersion, applicationVersionComparator: versionComparator, standardVersionComparator: versionComparator)
                
                let appcast = try SUAppcast(xmlData: testData, relativeTo: nil, stateResolver: stateResolver)
                XCTAssertFalse(appcast.items[0].isCriticalUpdate)
            }
        } catch let err as NSError {
            NSLog("%@", err)
            XCTFail(err.localizedDescription)
        }
    }
    
    func testInformationalUpdateVersions() {
        let testURL = Bundle(for: SUAppcastTest.self).url(forResource: "testappcast_info_updates", withExtension: "xml")!
        
        do {
            let testData = try Data(contentsOf: testURL)
            
            let versionComparator = SUStandardVersionComparator.default
            
            // Test informational updates from version 1.0
            do {
                let hostVersion = "1.0"
                let stateResolver = SPUAppcastItemStateResolver(hostVersion: hostVersion, applicationVersionComparator: versionComparator, standardVersionComparator: versionComparator)
                
                let appcast = try SUAppcast(xmlData: testData, relativeTo: nil, stateResolver: stateResolver)
                
                XCTAssertFalse(appcast.items[0].isInformationOnlyUpdate)
                XCTAssertFalse(appcast.items[1].isInformationOnlyUpdate)
                XCTAssertTrue(appcast.items[2].isInformationOnlyUpdate)
                XCTAssertTrue(appcast.items[3].isInformationOnlyUpdate)
                
                // Test delta updates inheriting informational only updates
                do {
                    let deltaUpdate = appcast.items[2].deltaUpdates!["2.0"]!
                    XCTAssertTrue(deltaUpdate.isInformationOnlyUpdate)
                }
            }
            
            // Test informational updates from version 2.3
            do {
                let hostVersion = "2.3"
                let stateResolver = SPUAppcastItemStateResolver(hostVersion: hostVersion, applicationVersionComparator: versionComparator, standardVersionComparator: versionComparator)
                
                let appcast = try SUAppcast(xmlData: testData, relativeTo: nil, stateResolver: stateResolver)
                
                XCTAssertFalse(appcast.items[1].isInformationOnlyUpdate)
            }
            
            // Test informational updates from version 2.4
            do {
                let hostVersion = "2.4"
                let stateResolver = SPUAppcastItemStateResolver(hostVersion: hostVersion, applicationVersionComparator: versionComparator, standardVersionComparator: versionComparator)
                
                let appcast = try SUAppcast(xmlData: testData, relativeTo: nil, stateResolver: stateResolver)
                
                XCTAssertTrue(appcast.items[1].isInformationOnlyUpdate)
            }
            
            // Test informational updates from version 2.5
            do {
                let hostVersion = "2.5"
                let stateResolver = SPUAppcastItemStateResolver(hostVersion: hostVersion, applicationVersionComparator: versionComparator, standardVersionComparator: versionComparator)
                
                let appcast = try SUAppcast(xmlData: testData, relativeTo: nil, stateResolver: stateResolver)
                
                XCTAssertTrue(appcast.items[1].isInformationOnlyUpdate)
            }
            
            // Test informational updates from version 2.6
            do {
                let hostVersion = "2.6"
                let stateResolver = SPUAppcastItemStateResolver(hostVersion: hostVersion, applicationVersionComparator: versionComparator, standardVersionComparator: versionComparator)
                
                let appcast = try SUAppcast(xmlData: testData, relativeTo: nil, stateResolver: stateResolver)
                
                XCTAssertFalse(appcast.items[1].isInformationOnlyUpdate)
            }
            
            // Test informational updates from version 0.5
            do {
                let hostVersion = "0.5"
                let stateResolver = SPUAppcastItemStateResolver(hostVersion: hostVersion, applicationVersionComparator: versionComparator, standardVersionComparator: versionComparator)
                
                let appcast = try SUAppcast(xmlData: testData, relativeTo: nil, stateResolver: stateResolver)
                
                XCTAssertFalse(appcast.items[1].isInformationOnlyUpdate)
            }
            
            // Test informational updates from version 0.4
            do {
                let hostVersion = "0.4"
                let stateResolver = SPUAppcastItemStateResolver(hostVersion: hostVersion, applicationVersionComparator: versionComparator, standardVersionComparator: versionComparator)
                
                let appcast = try SUAppcast(xmlData: testData, relativeTo: nil, stateResolver: stateResolver)
                
                XCTAssertTrue(appcast.items[1].isInformationOnlyUpdate)
            }
            
            // Test informational updates from version 0.0
            do {
                let hostVersion = "0.0"
                let stateResolver = SPUAppcastItemStateResolver(hostVersion: hostVersion, applicationVersionComparator: versionComparator, standardVersionComparator: versionComparator)
                
                let appcast = try SUAppcast(xmlData: testData, relativeTo: nil, stateResolver: stateResolver)
                
                XCTAssertTrue(appcast.items[1].isInformationOnlyUpdate)
            }
            
        } catch let err as NSError {
            NSLog("%@", err)
            XCTFail(err.localizedDescription)
        }
    }
    
    func testMinimumAutoupdateVersion() {
        let testURL = Bundle(for: SUAppcastTest.self).url(forResource: "testappcast_minimumAutoupdateVersion", withExtension: "xml")!
        
        do {
            let testData = try Data(contentsOf: testURL)
            
            let versionComparator = SUStandardVersionComparator()
            
            do {
                // Test appcast without a filter
                
                let hostVersion = "1.0"
                
                let stateResolver = SPUAppcastItemStateResolver(hostVersion: hostVersion, applicationVersionComparator: versionComparator, standardVersionComparator: versionComparator)
                let appcast = try SUAppcast(xmlData: testData, relativeTo: nil, stateResolver: stateResolver)
                
                XCTAssertEqual(2, appcast.items.count)
            }
            
            let currentDate = Date()
            // Because 3.0 has minimum autoupdate version of 2.0, we should be offered 2.0
            do {
                let hostVersion = "1.0"
                
                let stateResolver = SPUAppcastItemStateResolver(hostVersion: hostVersion, applicationVersionComparator: versionComparator, standardVersionComparator: versionComparator)
                let appcast = try SUAppcast(xmlData: testData, relativeTo: nil, stateResolver: stateResolver)
                
                let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: nil, skippedUpdate: nil, currentDate: currentDate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: true)
                
                XCTAssertEqual(1, supportedAppcast.items.count)
                
                let bestAppcastItem = SUAppcastDriver.bestItem(fromAppcastItems: supportedAppcast.items, getDeltaItem: nil, withHostVersion: hostVersion, comparator: versionComparator)
                
                XCTAssertEqual(bestAppcastItem.versionString, "2.0")
            }
            
            // We should be offered 3.0 if host version is 2.0
            do {
                let hostVersion = "2.0"
                
                let stateResolver = SPUAppcastItemStateResolver(hostVersion: hostVersion, applicationVersionComparator: versionComparator, standardVersionComparator: versionComparator)
                let appcast = try SUAppcast(xmlData: testData, relativeTo: nil, stateResolver: stateResolver)
                
                let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: nil, skippedUpdate: nil, currentDate: currentDate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: true)
                
                XCTAssertEqual(2, supportedAppcast.items.count)
                
                let bestAppcastItem = SUAppcastDriver.bestItem(fromAppcastItems: supportedAppcast.items, getDeltaItem: nil, withHostVersion: hostVersion, comparator: versionComparator)
                
                XCTAssertEqual(bestAppcastItem.versionString, "3.0")
            }
            
            // We should be offered 3.0 if host version is 2.5
            do {
                let hostVersion = "2.5"
                
                let stateResolver = SPUAppcastItemStateResolver(hostVersion: hostVersion, applicationVersionComparator: versionComparator, standardVersionComparator: versionComparator)
                let appcast = try SUAppcast(xmlData: testData, relativeTo: nil, stateResolver: stateResolver)
                
                let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: nil, skippedUpdate: nil, currentDate: currentDate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: true)
                
                XCTAssertEqual(2, supportedAppcast.items.count)
                
                let bestAppcastItem = SUAppcastDriver.bestItem(fromAppcastItems: supportedAppcast.items, getDeltaItem: nil, withHostVersion: hostVersion, comparator: versionComparator)
                
                XCTAssertEqual(bestAppcastItem.versionString, "3.0")
            }
            
            // Because 3.0 has minimum autoupdate version of 2.0, we would be be offered 2.0, but not if it has been skipped
            do {
                let hostVersion = "1.0"
                
                let stateResolver = SPUAppcastItemStateResolver(hostVersion: hostVersion, applicationVersionComparator: versionComparator, standardVersionComparator: versionComparator)
                let appcast = try SUAppcast(xmlData: testData, relativeTo: nil, stateResolver: stateResolver)
                
                // There should be no items if 2.0 is skipped from 1.0 and 3.0 fails minimum autoupdate version
                do {
                    let skippedUpdate = SPUSkippedUpdate(minorVersion: "2.0", majorVersion: nil, majorSubreleaseVersion: nil)
                    
                    let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: nil, skippedUpdate: skippedUpdate, currentDate: currentDate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: true)
                
                    XCTAssertEqual(0, supportedAppcast.items.count)
                }
                
                // Try again but allowing minimum autoupdate version to fail
                do {
                    let skippedUpdate = SPUSkippedUpdate(minorVersion: "2.0", majorVersion: nil, majorSubreleaseVersion: nil)
                    
                    let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: nil, skippedUpdate: skippedUpdate, currentDate: currentDate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: false)
                
                    XCTAssertEqual(1, supportedAppcast.items.count)
                    
                    let bestAppcastItem = SUAppcastDriver.bestItem(fromAppcastItems: supportedAppcast.items, getDeltaItem: nil, withHostVersion: hostVersion, comparator: versionComparator)
                    
                    XCTAssertEqual(bestAppcastItem.versionString, "3.0")
                }
                
                // Allow minimum autoupdate version to fail and only skip 3.0
                do {
                    let skippedUpdate = SPUSkippedUpdate(minorVersion: nil, majorVersion: "3.0", majorSubreleaseVersion: nil)
                    
                    let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: nil, skippedUpdate: skippedUpdate, currentDate: currentDate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: false)
                
                    XCTAssertEqual(1, supportedAppcast.items.count)
                    
                    let bestAppcastItem = SUAppcastDriver.bestItem(fromAppcastItems: supportedAppcast.items, getDeltaItem: nil, withHostVersion: hostVersion, comparator: versionComparator)
                    
                    XCTAssertEqual(bestAppcastItem.versionString, "2.0")
                }
                
                // Allow minimum autoupdate version to fail skipping both 2.0 and 3.0
                do {
                    let skippedUpdate = SPUSkippedUpdate(minorVersion: "2.0", majorVersion: "3.0", majorSubreleaseVersion: nil)
                    
                    let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: nil, skippedUpdate: skippedUpdate, currentDate: currentDate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: false)
                
                    XCTAssertEqual(0, supportedAppcast.items.count)
                }
                
                // Allow minimum autoupdate version to fail and only skip "2.5"
                // This should implicitly only skip 2.0
                do {
                    let skippedUpdate = SPUSkippedUpdate(minorVersion: "2.5", majorVersion: nil, majorSubreleaseVersion: nil)
                    
                    let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: nil, skippedUpdate: skippedUpdate, currentDate: currentDate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: false)
                
                    XCTAssertEqual(1, supportedAppcast.items.count)
                    
                    let bestAppcastItem = SUAppcastDriver.bestItem(fromAppcastItems: supportedAppcast.items, getDeltaItem: nil, withHostVersion: hostVersion, comparator: versionComparator)
                    
                    XCTAssertEqual(bestAppcastItem.versionString, "3.0")
                }
                
                // This should not skip anything but require passing minimum autoupdate version
                do {
                    let skippedUpdate = SPUSkippedUpdate(minorVersion: "1.5", majorVersion: nil, majorSubreleaseVersion: nil)
                    
                    let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: nil, skippedUpdate: skippedUpdate, currentDate: currentDate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: true)
                
                    XCTAssertEqual(1, supportedAppcast.items.count)
                    
                    let bestAppcastItem = SUAppcastDriver.bestItem(fromAppcastItems: supportedAppcast.items, getDeltaItem: nil, withHostVersion: hostVersion, comparator: versionComparator)
                    
                    XCTAssertEqual(bestAppcastItem.versionString, "2.0")
                }
                
                // This should not skip anything but allow failing minimum autoupdate version
                do {
                    let skippedUpdate = SPUSkippedUpdate(minorVersion: "1.5", majorVersion: nil, majorSubreleaseVersion: nil)
                    
                    let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: nil, skippedUpdate: skippedUpdate, currentDate: currentDate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: false)
                
                    XCTAssertEqual(2, supportedAppcast.items.count)
                    
                    let bestAppcastItem = SUAppcastDriver.bestItem(fromAppcastItems: supportedAppcast.items, getDeltaItem: nil, withHostVersion: hostVersion, comparator: versionComparator)
                    
                    XCTAssertEqual(bestAppcastItem.versionString, "3.0")
                }
                
                // This should not skip anything but require passing minimum autoupdate version
                do {
                    let skippedUpdate = SPUSkippedUpdate(minorVersion: "1.5", majorVersion: "1.0", majorSubreleaseVersion: nil)
                    
                    let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: nil, skippedUpdate: skippedUpdate, currentDate: currentDate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: true)
                
                    XCTAssertEqual(1, supportedAppcast.items.count)
                    
                    let bestAppcastItem = SUAppcastDriver.bestItem(fromAppcastItems: supportedAppcast.items, getDeltaItem: nil, withHostVersion: hostVersion, comparator: versionComparator)
                    
                    XCTAssertEqual(bestAppcastItem.versionString, "2.0")
                }
                
                // This should not skip anything but allow failing minimum autoupdate version
                do {
                    let skippedUpdate = SPUSkippedUpdate(minorVersion: "1.5", majorVersion: "1.0", majorSubreleaseVersion: nil)
                    
                    let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: nil, skippedUpdate: skippedUpdate, currentDate: currentDate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: false)
                
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
    
    func testMinimumAutoupdateVersionAdvancedSkipping() {
        let testURL = Bundle(for: SUAppcastTest.self).url(forResource: "testappcast_minimumAutoupdateVersionSkipping", withExtension: "xml")!
        
        do {
            let testData = try Data(contentsOf: testURL)
            
            let versionComparator = SUStandardVersionComparator()
            
            do {
                // Test appcast without a filter
                
                let hostVersion = "1.0"
                
                let stateResolver = SPUAppcastItemStateResolver(hostVersion: hostVersion, applicationVersionComparator: versionComparator, standardVersionComparator: versionComparator)
                let appcast = try SUAppcast(xmlData: testData, relativeTo: nil, stateResolver: stateResolver)
                
                XCTAssertEqual(5, appcast.items.count)
            }
            
            let currentDate = Date()
            // Because 3.0 has minimum autoupdate version of 3.0, and 4.0 has minimum autoupdate version of 4.0, we should be offered 2.0
            do {
                let hostVersion = "1.0"
                
                let stateResolver = SPUAppcastItemStateResolver(hostVersion: hostVersion, applicationVersionComparator: versionComparator, standardVersionComparator: versionComparator)
                let appcast = try SUAppcast(xmlData: testData, relativeTo: nil, stateResolver: stateResolver)
                
                let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: nil, skippedUpdate: nil, currentDate: currentDate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: true)
                
                XCTAssertEqual(1, supportedAppcast.items.count)
                
                let bestAppcastItem = SUAppcastDriver.bestItem(fromAppcastItems: supportedAppcast.items, getDeltaItem: nil, withHostVersion: hostVersion, comparator: versionComparator)
                
                XCTAssertEqual(bestAppcastItem.versionString, "2.0")
            }
            
            // Allow minimum autoupdate version to fail and only skip major version "3.0"
            // This should skip all 3.x versions, but not 4.x versions nor 2.x versions
            do {
                let hostVersion = "1.0"
                
                let stateResolver = SPUAppcastItemStateResolver(hostVersion: hostVersion, applicationVersionComparator: versionComparator, standardVersionComparator: versionComparator)
                let appcast = try SUAppcast(xmlData: testData, relativeTo: nil, stateResolver: stateResolver)
                
                let skippedUpdate = SPUSkippedUpdate(minorVersion: nil, majorVersion: "3.0", majorSubreleaseVersion: nil)
                
                let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: nil, skippedUpdate: skippedUpdate, currentDate: currentDate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: false)
            
                XCTAssertEqual(3, supportedAppcast.items.count)
                
                let bestAppcastItem = SUAppcastDriver.bestItem(fromAppcastItems: supportedAppcast.items, getDeltaItem: nil, withHostVersion: hostVersion, comparator: versionComparator)
                
                XCTAssertEqual(bestAppcastItem.versionString, "4.1")
            }
            
            // Allow minimum autoupdate version to pass and only skip major version "3.0"
            // This should only return back the latest minor version available
            do {
                let hostVersion = "1.0"
                
                let stateResolver = SPUAppcastItemStateResolver(hostVersion: hostVersion, applicationVersionComparator: versionComparator, standardVersionComparator: versionComparator)
                let appcast = try SUAppcast(xmlData: testData, relativeTo: nil, stateResolver: stateResolver)
                
                let skippedUpdate = SPUSkippedUpdate(minorVersion: nil, majorVersion: "3.0", majorSubreleaseVersion: nil)
                
                let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: nil, skippedUpdate: skippedUpdate, currentDate: currentDate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: true)
            
                XCTAssertEqual(1, supportedAppcast.items.count)
                
                let bestAppcastItem = SUAppcastDriver.bestItem(fromAppcastItems: supportedAppcast.items, getDeltaItem: nil, withHostVersion: hostVersion, comparator: versionComparator)
                
                XCTAssertEqual(bestAppcastItem.versionString, "2.0")
            }
            
            // Allow minimum autoupdate version to fail and only skip major version "4.0"
            // This should skip all 3.x versions and 4.x versions but not 2.x versions
            do {
                let hostVersion = "1.0"
                
                let stateResolver = SPUAppcastItemStateResolver(hostVersion: hostVersion, applicationVersionComparator: versionComparator, standardVersionComparator: versionComparator)
                let appcast = try SUAppcast(xmlData: testData, relativeTo: nil, stateResolver: stateResolver)
                
                let skippedUpdate = SPUSkippedUpdate(minorVersion: nil, majorVersion: "4.0", majorSubreleaseVersion: nil)
                
                let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: nil, skippedUpdate: skippedUpdate, currentDate: currentDate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: false)
            
                XCTAssertEqual(1, supportedAppcast.items.count)
                
                let bestAppcastItem = SUAppcastDriver.bestItem(fromAppcastItems: supportedAppcast.items, getDeltaItem: nil, withHostVersion: hostVersion, comparator: versionComparator)
                
                XCTAssertEqual(bestAppcastItem.versionString, "2.0")
            }
        } catch let err as NSError {
            NSLog("%@", err)
            XCTFail(err.localizedDescription)
        }
    }
    
    func testMinimumAutoupdateVersionIgnoringSkipping() {
        let testURL = Bundle(for: SUAppcastTest.self).url(forResource: "testappcast_minimumAutoupdateVersionSkipping2", withExtension: "xml")!
        
        do {
            let testData = try Data(contentsOf: testURL)
            
            let versionComparator = SUStandardVersionComparator()
            
            let currentDate = Date()
            
            do {
                let hostVersion = "1.0"
                
                let stateResolver = SPUAppcastItemStateResolver(hostVersion: hostVersion, applicationVersionComparator: versionComparator, standardVersionComparator: versionComparator)
                let appcast = try SUAppcast(xmlData: testData, relativeTo: nil, stateResolver: stateResolver)
                
                // Allow minimum autoupdate version to fail and only skip major version "3.0" with no subrelease version
                // This should skip all 3.x versions except for 3.9 which ignores skipped upgrades below 3.5, but not 4.x versions nor 2.x versions
                do {
                    let skippedUpdate = SPUSkippedUpdate(minorVersion: nil, majorVersion: "3.0", majorSubreleaseVersion: nil)
                    
                    let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: nil, skippedUpdate: skippedUpdate, currentDate: currentDate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: false)
                
                    XCTAssertEqual(4, supportedAppcast.items.count)
                    
                    XCTAssertEqual(supportedAppcast.items[0].versionString, "4.1")
                    XCTAssertEqual(supportedAppcast.items[1].versionString, "4.0")
                    XCTAssertEqual(supportedAppcast.items[2].versionString, "3.9")
                    XCTAssertEqual(supportedAppcast.items[3].versionString, "2.0")
                    
                    let bestAppcastItem = SUAppcastDriver.bestItem(fromAppcastItems: supportedAppcast.items, getDeltaItem: nil, withHostVersion: hostVersion, comparator: versionComparator)
                    
                    XCTAssertEqual(bestAppcastItem.versionString, "4.1")
                }
                
                // Allow minimum autoupdate version to fail and only skip major version "3.0" with subrelease version 3.4
                // This should skip all 3.x versions except for 3.9 which ignores skipped upgrades below 3.5, but not 4.x versions nor 2.x versions
                do {
                    let skippedUpdate = SPUSkippedUpdate(minorVersion: nil, majorVersion: "3.4", majorSubreleaseVersion: nil)
                    
                    let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: nil, skippedUpdate: skippedUpdate, currentDate: currentDate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: false)
                
                    XCTAssertEqual(4, supportedAppcast.items.count)
                    
                    XCTAssertEqual(supportedAppcast.items[0].versionString, "4.1")
                    XCTAssertEqual(supportedAppcast.items[1].versionString, "4.0")
                    XCTAssertEqual(supportedAppcast.items[2].versionString, "3.9")
                    XCTAssertEqual(supportedAppcast.items[3].versionString, "2.0")
                    
                    let bestAppcastItem = SUAppcastDriver.bestItem(fromAppcastItems: supportedAppcast.items, getDeltaItem: nil, withHostVersion: hostVersion, comparator: versionComparator)
                    
                    XCTAssertEqual(bestAppcastItem.versionString, "4.1")
                }
                
                // Allow minimum autoupdate version to fail and only skip major version "3.0" with subrelease version 3.5
                // This should skip all 3.x versions, but not 4.x versions nor 2.x versions
                do {
                    let skippedUpdate = SPUSkippedUpdate(minorVersion: nil, majorVersion: "3.0", majorSubreleaseVersion: "3.5")
                    
                    let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: nil, skippedUpdate: skippedUpdate, currentDate: currentDate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: false)
                
                    XCTAssertEqual(3, supportedAppcast.items.count)
                    
                    XCTAssertEqual(supportedAppcast.items[0].versionString, "4.1")
                    XCTAssertEqual(supportedAppcast.items[1].versionString, "4.0")
                    XCTAssertEqual(supportedAppcast.items[2].versionString, "2.0")
                    
                    let bestAppcastItem = SUAppcastDriver.bestItem(fromAppcastItems: supportedAppcast.items, getDeltaItem: nil, withHostVersion: hostVersion, comparator: versionComparator)
                    
                    XCTAssertEqual(bestAppcastItem.versionString, "4.1")
                }
                
                // Allow minimum autoupdate version to fail and only skip major version "3.0" with subrelease version 3.5.1
                // This should skip all 3.x versions, but not 4.x versions nor 2.x versions
                do {
                    let skippedUpdate = SPUSkippedUpdate(minorVersion: nil, majorVersion: "3.0", majorSubreleaseVersion: "3.5.1")
                    
                    let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: nil, skippedUpdate: skippedUpdate, currentDate: currentDate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: false)
                
                    XCTAssertEqual(3, supportedAppcast.items.count)
                    
                    XCTAssertEqual(supportedAppcast.items[0].versionString, "4.1")
                    XCTAssertEqual(supportedAppcast.items[1].versionString, "4.0")
                    XCTAssertEqual(supportedAppcast.items[2].versionString, "2.0")
                    
                    let bestAppcastItem = SUAppcastDriver.bestItem(fromAppcastItems: supportedAppcast.items, getDeltaItem: nil, withHostVersion: hostVersion, comparator: versionComparator)
                    
                    XCTAssertEqual(bestAppcastItem.versionString, "4.1")
                }
                
                // Allow minimum autoupdate version to fail and only skip major version "4.0" with subrelease version 4.0
                // This should skip all 3.x versions and 4.x versions, but not 2.x versions
                do {
                    let skippedUpdate = SPUSkippedUpdate(minorVersion: nil, majorVersion: "4.0", majorSubreleaseVersion: "4.0")
                    
                    let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: nil, skippedUpdate: skippedUpdate, currentDate: currentDate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: false)
                
                    XCTAssertEqual(1, supportedAppcast.items.count)
                    
                    XCTAssertEqual(supportedAppcast.items[0].versionString, "2.0")
                    
                    let bestAppcastItem = SUAppcastDriver.bestItem(fromAppcastItems: supportedAppcast.items, getDeltaItem: nil, withHostVersion: hostVersion, comparator: versionComparator)
                    
                    XCTAssertEqual(bestAppcastItem.versionString, "2.0")
                }
                
                // Allow minimum autoupdate version to fail and only skip major version "4.0" with subrelease version 4.0, and skip minor version 2.1
                // This should skip everything
                do {
                    let skippedUpdate = SPUSkippedUpdate(minorVersion: "2.1", majorVersion: "4.0", majorSubreleaseVersion: "4.0")
                    
                    let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: nil, skippedUpdate: skippedUpdate, currentDate: currentDate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: false)
                
                    XCTAssertEqual(0, supportedAppcast.items.count)
                }
            }
        } catch let err as NSError {
            NSLog("%@", err)
            XCTFail(err.localizedDescription)
        }
    }
    
    func testPhasedGroupRollouts() {
        let testURL = Bundle(for: SUAppcastTest.self).url(forResource: "testappcast_phasedRollout", withExtension: "xml")!
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "E, dd MMM yyyy HH:mm:ss Z"
        dateFormatter.locale = Locale(identifier: "en_US")
        
        do {
            let testData = try Data(contentsOf: testURL)
            
            let versionComparator = SUStandardVersionComparator()
            
            // Because 3.0 has minimum autoupdate version of 2.0, we should be offered 2.0
            do {
                let hostVersion = "1.0"
                
                let stateResolver = SPUAppcastItemStateResolver(hostVersion: hostVersion, applicationVersionComparator: versionComparator, standardVersionComparator: versionComparator)
                let appcast = try SUAppcast(xmlData: testData, relativeTo: nil, stateResolver: stateResolver)
                
                do {
                    // Test no group
                    let group: NSNumber? = nil
                    let currentDate = Date()
                    let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: group, skippedUpdate: nil, currentDate: currentDate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: true)
                    
                    XCTAssertEqual(1, supportedAppcast.items.count)
                    XCTAssertEqual("2.0", supportedAppcast.items[0].versionString)
                }
                
                do {
                    // Test 0 group with current date (way ahead of pubDate)
                    let group: NSNumber? = nil
                    let currentDate = Date()
                    let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: group, skippedUpdate: nil, currentDate: currentDate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: true)
                    
                    XCTAssertEqual(1, supportedAppcast.items.count)
                }
                
                do {
                    // Test 6th group with current date (way ahead of pubDate)
                    let group = 6 as NSNumber
                    let currentDate = Date()
                    let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: group, skippedUpdate: nil, currentDate: currentDate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: true)
                    
                    XCTAssertEqual(1, supportedAppcast.items.count)
                }
                
                do {
                    let currentDate = dateFormatter.date(from: "Wed, 23 Jul 2014 15:20:11 +0000")!
                    
                    do {
                        // Test group 0 with current date 3 days before rollout
                        // No update should be found
                        let group = 0 as NSNumber
                        
                        let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: group, skippedUpdate: nil, currentDate: currentDate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: true)
                        
                        XCTAssertEqual(0, supportedAppcast.items.count)
                    }
                    
                    do {
                        // Test group 6 with current date 3 days before rollout
                        // No update should be found still
                        let group = 6 as NSNumber
                        
                        let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: group, skippedUpdate: nil, currentDate: currentDate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: true)
                        
                        XCTAssertEqual(0, supportedAppcast.items.count)
                    }
                }
                
                do {
                    let currentDate = dateFormatter.date(from: "Mon, 28 Jul 2014 15:20:11 +0000")!
                    
                    do {
                        // Test group 0 with current date 2 days after rollout
                        let group = 0 as NSNumber
                        
                        let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: group, skippedUpdate: nil, currentDate: currentDate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: true)
                        
                        XCTAssertEqual(1, supportedAppcast.items.count)
                    }
                    
                    do {
                        // Test group 1 with current date 3 days after rollout
                        let group = 1 as NSNumber
                        
                        let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: group, skippedUpdate: nil, currentDate: currentDate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: true)
                        
                        XCTAssertEqual(1, supportedAppcast.items.count)
                    }
                    
                    do {
                        // Test group 2 with current date 3 days after rollout
                        let group = 2 as NSNumber
                        
                        let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: group, skippedUpdate: nil, currentDate: currentDate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: true)
                        
                        XCTAssertEqual(1, supportedAppcast.items.count)
                    }
                    
                    do {
                        // Test group 3 with current date 3 days after rollout
                        let group = 3 as NSNumber
                        
                        let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: group, skippedUpdate: nil, currentDate: currentDate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: true)
                        
                        XCTAssertEqual(0, supportedAppcast.items.count)
                    }
                    
                    do {
                        // Test group 6 with current date 3 days after rollout
                        let group = 6 as NSNumber
                        
                        let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: group, skippedUpdate: nil, currentDate: currentDate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: true)
                        
                        XCTAssertEqual(0, supportedAppcast.items.count)
                    }
                }
                
                // Test critical updates which ignore phased rollouts
                do {
                    let hostVersion = "2.0"
                    
                    let stateResolver = SPUAppcastItemStateResolver(hostVersion: hostVersion, applicationVersionComparator: versionComparator, standardVersionComparator: versionComparator)
                    let appcast = try SUAppcast(xmlData: testData, relativeTo: nil, stateResolver: stateResolver)
                    
                    do {
                        // Test no group
                        let group: NSNumber? = nil
                        let currentDate = Date()
                        let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: group, skippedUpdate: nil, currentDate: currentDate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: true)
                        
                        XCTAssertEqual(2, supportedAppcast.items.count)
                        XCTAssertEqual("3.0", supportedAppcast.items[0].versionString)
                    }
                    
                    do {
                        let currentDate = dateFormatter.date(from: "Wed, 23 Jul 2014 15:20:11 +0000")!
                        
                        do {
                            // Test group 0 with current date 3 days before rollout
                            let group = 0 as NSNumber
                            
                            let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: group, skippedUpdate: nil, currentDate: currentDate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: true)
                            
                            XCTAssertEqual(1, supportedAppcast.items.count)
                            XCTAssertEqual("3.0", supportedAppcast.items[0].versionString)
                        }
                    }
                    
                    do {
                        let currentDate = dateFormatter.date(from: "Mon, 28 Jul 2014 15:20:11 +0000")!
                        
                        do {
                            // Test group 6 with current date 3 days after rollout
                            let group = 6 as NSNumber
                            
                            let supportedAppcast = SUAppcastDriver.filterSupportedAppcast(appcast, phasedUpdateGroup: group, skippedUpdate: nil, currentDate: currentDate, hostVersion: hostVersion, versionComparator: versionComparator, testOSVersion: true, testMinimumAutoupdateVersion: true)
                            
                            XCTAssertEqual(1, supportedAppcast.items.count)
                            XCTAssertEqual("3.0", supportedAppcast.items[0].versionString)
                        }
                    }
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
        
        let preferredLanguage = Bundle.preferredLocalizations(from: ["en", "es"])[0]
        
        NSLog("Using preferred locale %@", preferredLanguage)
        
        let expectedReleaseNotesLink = (preferredLanguage == "es") ? "https://sparkle-project.org/notes.es.html" : "https://sparkle-project.org/notes.en.html"

        do {
            let testFileData = try Data(contentsOf: testFileUrl)
            
            let stateResolver = SPUAppcastItemStateResolver(hostVersion: "1.0", applicationVersionComparator: SUStandardVersionComparator.default, standardVersionComparator: SUStandardVersionComparator.default)
            
            let fullAppcast = try SUAppcast(xmlData: testFileData, relativeTo: testFileUrl, stateResolver: stateResolver)
            
            do {
                let appcast = SUAppcastDriver.filterAppcast(fullAppcast, forMacOSAndAllowedChannels: ["english-later"])
                let items = appcast.items
                XCTAssertEqual(items.count, 1)
                XCTAssertEqual(items[0].versionString, "6.0")
                XCTAssertEqual(expectedReleaseNotesLink, items[0].releaseNotesURL!.absoluteString)
            }
            
            do {
                let appcast = SUAppcastDriver.filterAppcast(fullAppcast, forMacOSAndAllowedChannels: ["english-first"])
                let items = appcast.items
                XCTAssertEqual(items.count, 1)
                XCTAssertEqual(items[0].versionString, "6.1")
                XCTAssertEqual(expectedReleaseNotesLink, items[0].releaseNotesURL!.absoluteString)
            }
            
            do {
                let appcast = SUAppcastDriver.filterAppcast(fullAppcast, forMacOSAndAllowedChannels: ["english-first-implicit"])
                let items = appcast.items
                XCTAssertEqual(items.count, 1)
                XCTAssertEqual(items[0].versionString, "6.2")
                XCTAssertEqual(expectedReleaseNotesLink, items[0].releaseNotesURL!.absoluteString)
            }
            
            do {
                let appcast = SUAppcastDriver.filterAppcast(fullAppcast, forMacOSAndAllowedChannels: ["english-later-implicit"])
                let items = appcast.items
                XCTAssertEqual(items.count, 1)
                XCTAssertEqual(items[0].versionString, "6.3")
                XCTAssertEqual(expectedReleaseNotesLink, items[0].releaseNotesURL!.absoluteString)
            }
        } catch let err as NSError {
            NSLog("%@", err)
            XCTFail(err.localizedDescription)
        }
    }

    func testNamespaces() {
        let testFile = Bundle(for: SUAppcastTest.self).path(forResource: "testnamespaces", ofType: "xml")!
        let testData = NSData(contentsOfFile: testFile)!

        do {
            let stateResolver = SPUAppcastItemStateResolver(hostVersion: "1.0", applicationVersionComparator: SUStandardVersionComparator.default, standardVersionComparator: SUStandardVersionComparator.default)
            
            let appcast = try SUAppcast(xmlData: testData as Data, relativeTo: nil, stateResolver: stateResolver)
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
    
    func testLinks() {
        let testFile = Bundle(for: SUAppcastTest.self).path(forResource: "test-links", ofType: "xml")!
        let testData = NSData(contentsOfFile: testFile)!
        
        do {
            let baseURL: URL? = nil
            
            let stateResolver = SPUAppcastItemStateResolver(hostVersion: "1.0", applicationVersionComparator: SUStandardVersionComparator.default, standardVersionComparator: SUStandardVersionComparator.default)
            
            let appcast = try SUAppcast(xmlData: testData as Data, relativeTo: baseURL, stateResolver: stateResolver)
            let items = appcast.items
            
            XCTAssertEqual(3, items.count)
            
            // Test https
            XCTAssertEqual("https://sparkle-project.org/notes/relnote-3.0.txt", items[0].releaseNotesURL?.absoluteString)
            XCTAssertEqual("https://sparkle-project.org/fullnotes.txt", items[0].fullReleaseNotesURL?.absoluteString)
            XCTAssertEqual("https://sparkle-project.org", items[0].infoURL?.absoluteString)
            XCTAssertEqual("https://sparkle-project.org/release-3.0.zip", items[0].fileURL?.absoluteString)
            
            // Test http
            XCTAssertEqual("http://sparkle-project.org/notes/relnote-2.0.txt", items[1].releaseNotesURL?.absoluteString)
            XCTAssertEqual("http://sparkle-project.org/fullnotes.txt", items[1].fullReleaseNotesURL?.absoluteString)
            XCTAssertEqual("http://sparkle-project.org", items[1].infoURL?.absoluteString)
            XCTAssertEqual("http://sparkle-project.org/release-2.0.zip", items[1].fileURL?.absoluteString)
            
            // Test bad file URLs
            XCTAssertEqual(nil, items[2].releaseNotesURL?.absoluteString)
            XCTAssertEqual(nil, items[2].fullReleaseNotesURL?.absoluteString)
            XCTAssertEqual(nil, items[2].infoURL?.absoluteString)
            XCTAssertEqual("https://sparkle-project.org/release-1.0.zip", items[2].fileURL?.absoluteString)
            
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
            
            let stateResolver = SPUAppcastItemStateResolver(hostVersion: "1.0", applicationVersionComparator: SUStandardVersionComparator.default, standardVersionComparator: SUStandardVersionComparator.default)
            
            let appcast = try SUAppcast(xmlData: testData as Data, relativeTo: baseURL, stateResolver: stateResolver)
            let items = appcast.items

            XCTAssertEqual(4, items.count)

            XCTAssertEqual("https://fake.sparkle-project.org/updates/release-3.0.zip", items[0].fileURL?.absoluteString)
            XCTAssertEqual("https://fake.sparkle-project.org/updates/notes/relnote-3.0.txt", items[0].releaseNotesURL?.absoluteString)

            XCTAssertEqual(2, items[0].deltaUpdates!.count)

            XCTAssertEqual("https://fake.sparkle-project.org/updates/3.0_from_2.0.delta", items[0].deltaUpdates!["2.0"]!.fileURL?.absoluteString)
            XCTAssertEqual("https://fake.sparkle-project.org/updates/3.0_from_1.0.delta", items[0].deltaUpdates!["1.0"]!.fileURL?.absoluteString)

            XCTAssertEqual("https://fake.sparkle-project.org/info/info-2.0.txt", items[1].infoURL?.absoluteString)
            
            XCTAssertEqual("https://fake.sparkle-project.org/updates/notes/fullnotes.txt", items[2].fullReleaseNotesURL?.absoluteString)
            
            // If a different base URL is in the feed, we should respect the base URL in the feed
            XCTAssertEqual("https://sparkle-project.org/releasenotes.html", items[3].fullReleaseNotesURL?.absoluteString)

        } catch let err as NSError {
            NSLog("%@", err)
            XCTFail(err.localizedDescription)
        }
    }

    func testDangerousLink() {
        let testFile = Bundle(for: SUAppcastTest.self).path(forResource: "test-dangerous-link", ofType: "xml")!
        let testData = NSData(contentsOfFile: testFile)!
        
        do {
            let baseURL: URL? = nil
            
            let stateResolver = SPUAppcastItemStateResolver(hostVersion: "1.0", applicationVersionComparator: SUStandardVersionComparator.default, standardVersionComparator: SUStandardVersionComparator.default)
            
            let _ = try SUAppcast(xmlData: testData as Data, relativeTo: baseURL, stateResolver: stateResolver)
            
            XCTFail("Appcast creation should fail when encountering dangerous link")
        } catch let err as NSError {
            NSLog("Expected error: %@", err)
            XCTAssertNotNil(err)
        }
    }
}
