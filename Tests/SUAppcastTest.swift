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
            
            XCTAssertEqual(2, items.count);
            XCTAssertEqual("Version 3.0", items[0].title);
            XCTAssertNil(items[0].itemDescription);
            
            XCTAssertEqual("Version 2.0", items[1].title);
            XCTAssertEqual("desc", items[1].itemDescription);
        } catch let err as NSError {
            NSLog("%@", err);
            XCTFail(err.localizedDescription);
        }
    }
}
