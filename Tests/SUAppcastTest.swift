//
//  SUAppcastTest.swift
//  Sparkle
//
//  Created by Kornel on 17/02/2016.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

import XCTest
import Sparkle;

class SUAppcastTest: XCTestCase {

    func testExample() {
        let appcast = SUAppcast();
        let testFile = NSBundle(forClass: SUAppcastTest.self).pathForResource("testappcast", ofType: "xml")!;
        let testFileUrl = NSURL(fileURLWithPath: testFile);
        XCTAssertNotNil(testFileUrl);
        
        do {
            let items = try appcast.parseAppcastItemsFromXMLFile(testFileUrl) as! [SUAppcastItem];
            
            XCTAssertEqual(4, items.count);
            
            XCTAssertEqual("Version 2.0", items[0].title);
            XCTAssertEqual("desc", items[0].itemDescription);
            
            // This is the best release matching our system version
            XCTAssertEqual("Version 3.0", items[1].title);
            XCTAssertNil(items[1].itemDescription);
            
            XCTAssertEqual("Version 4.0", items[2].title);
            XCTAssertNil(items[2].itemDescription);
            
            XCTAssertEqual("Version 5.0", items[3].title);
            XCTAssertNil(items[3].itemDescription);
            
            let bestAppcastItem = SUBasicUpdateDriver.bestAppcastItemFromAppcastItems(items, withComparator: SUStandardVersionComparator.defaultComparator())
            
            XCTAssertEqual(bestAppcastItem, items[1])
        } catch let err as NSError {
            NSLog("%@", err);
            XCTFail(err.localizedDescription);
        }
    }
}
