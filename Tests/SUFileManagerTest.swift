//
//  SUFileManagerTest.swift
//  Sparkle
//
//  Created by Mayur Pawashe on 9/26/15.
//  Copyright © 2015 Sparkle Project. All rights reserved.
//

import XCTest

class SUFileManagerTest: XCTestCase
{
    func makeTempFiles(testBlock: (SUFileManager, NSURL, NSURL, NSURL, NSURL) -> Void)
    {
        let fileManager = SUFileManager()
        
        let tempDirectoryURL = try! fileManager.makeTemporaryDirectoryWithPreferredName("Sparkle Unit Test Data", appropriateForDirectoryURL: NSURL(fileURLWithPath: NSHomeDirectory()))
        
        defer {
            try! fileManager.removeItemAtURL(tempDirectoryURL)
        }
        
        let ordinaryFileURL = tempDirectoryURL.URLByAppendingPathComponent("a file written by sparkles unit tests")
        try! "foo".dataUsingEncoding(NSUTF8StringEncoding)!.writeToURL(ordinaryFileURL, options: .DataWritingAtomic)
        
        let directoryURL = tempDirectoryURL.URLByAppendingPathComponent("a directory written by sparkles unit tests")
        try! NSFileManager.defaultManager().createDirectoryAtURL(directoryURL, withIntermediateDirectories: false, attributes: nil)
        
        let fileInDirectoryURL = directoryURL.URLByAppendingPathComponent("a file inside a directory written by sparkles unit tests")
        try! "bar baz".dataUsingEncoding(NSUTF8StringEncoding)!.writeToURL(fileInDirectoryURL, options: .DataWritingAtomic)
        
        testBlock(fileManager, tempDirectoryURL, ordinaryFileURL, directoryURL, fileInDirectoryURL)
    }
    
    func testMoveFiles()
    {
        makeTempFiles() { fileManager, rootURL, ordinaryFileURL, directoryURL, fileInDirectoryURL in
            XCTAssertNil(try? fileManager.moveItemAtURL(ordinaryFileURL, toURL: directoryURL))
            XCTAssertNil(try? fileManager.moveItemAtURL(rootURL.URLByAppendingPathComponent("does not exist"), toURL: directoryURL))
            
            let newFileURL = (ordinaryFileURL.URLByDeletingLastPathComponent?.URLByAppendingPathComponent("new file"))!
            try! fileManager.moveItemAtURL(ordinaryFileURL, toURL: newFileURL)
            XCTAssertFalse(fileManager._itemExistsAtURL(ordinaryFileURL))
            XCTAssertTrue(fileManager._itemExistsAtURL(newFileURL))
            
            let newDirectoryURL = (ordinaryFileURL.URLByDeletingLastPathComponent?.URLByAppendingPathComponent("new directory"))!
            try! fileManager.moveItemAtURL(directoryURL, toURL: newDirectoryURL)
            XCTAssertFalse(fileManager._itemExistsAtURL(directoryURL))
            XCTAssertTrue(fileManager._itemExistsAtURL(newDirectoryURL))
            XCTAssertFalse(fileManager._itemExistsAtURL(fileInDirectoryURL))
            XCTAssertTrue(fileManager._itemExistsAtURL(newDirectoryURL.URLByAppendingPathComponent(fileInDirectoryURL.lastPathComponent!)))
        }
    }
    
    func testMoveFilesToTrash()
    {
        makeTempFiles() { fileManager, rootURL, ordinaryFileURL, directoryURL, fileInDirectoryURL in
            XCTAssertNil(try? fileManager.moveItemAtURLToTrash(rootURL.URLByAppendingPathComponent("does not exist")))
            
            let trashURL = try! NSFileManager.defaultManager().URLForDirectory(.TrashDirectory, inDomain: .UserDomainMask, appropriateForURL: nil, create: false)
            
            try! fileManager.moveItemAtURLToTrash(ordinaryFileURL)
            XCTAssertFalse(fileManager._itemExistsAtURL(ordinaryFileURL))
            
            let ordinaryFileTrashURL = trashURL.URLByAppendingPathComponent(ordinaryFileURL.lastPathComponent!)
            XCTAssertTrue(fileManager._itemExistsAtURL(ordinaryFileTrashURL))
            try! fileManager.removeItemAtURL(ordinaryFileTrashURL)
            
            try! fileManager.moveItemAtURLToTrash(directoryURL)
            XCTAssertFalse(fileManager._itemExistsAtURL(directoryURL))
            XCTAssertFalse(fileManager._itemExistsAtURL(fileInDirectoryURL))
            
            let directoryTrashURL = trashURL.URLByAppendingPathComponent(directoryURL.lastPathComponent!)
            XCTAssertTrue(fileManager._itemExistsAtURL(directoryTrashURL))
            XCTAssertTrue(fileManager._itemExistsAtURL(directoryTrashURL.URLByAppendingPathComponent(fileInDirectoryURL.lastPathComponent!)))
            
            try! fileManager.removeItemAtURL(directoryTrashURL)
        }
    }

    func testRemoveFiles()
    {
        makeTempFiles() { fileManager, rootURL, ordinaryFileURL, directoryURL, fileInDirectoryURL in
            XCTAssertNil(try? fileManager.removeItemAtURL(rootURL.URLByAppendingPathComponent("does not exist")))
            
            try! fileManager.removeItemAtURL(ordinaryFileURL)
            XCTAssertFalse(fileManager._itemExistsAtURL(ordinaryFileURL))
            
            try! fileManager.removeItemAtURL(directoryURL)
            XCTAssertFalse(fileManager._itemExistsAtURL(directoryURL))
            XCTAssertFalse(fileManager._itemExistsAtURL(fileInDirectoryURL))
        }
    }
    
    func testReleaseFilesFromQuarantine()
    {
        makeTempFiles() { fileManager, rootURL, ordinaryFileURL, directoryURL, fileInDirectoryURL in
            try! fileManager.releaseItemFromQuarantineWithoutAuthenticationAtRootURL(ordinaryFileURL)
            try! fileManager.releaseItemFromQuarantineWithoutAuthenticationAtRootURL(directoryURL)
            
            let quarantineData = "does not really matter what is here".cStringUsingEncoding(NSUTF8StringEncoding)!
            let quarantineDataLength = Int(strlen(quarantineData))
            
            XCTAssertEqual(0, setxattr(ordinaryFileURL.path!, SUAppleQuarantineIdentifier, quarantineData, quarantineDataLength, 0, XATTR_CREATE))
            XCTAssertGreaterThan(getxattr(ordinaryFileURL.path!, SUAppleQuarantineIdentifier, nil, 0, 0, XATTR_NOFOLLOW), 0)
            
            try! fileManager.releaseItemFromQuarantineWithoutAuthenticationAtRootURL(ordinaryFileURL)
            XCTAssertEqual(-1, getxattr(ordinaryFileURL.path!, SUAppleQuarantineIdentifier, nil, 0, 0, XATTR_NOFOLLOW))
            
            XCTAssertEqual(0, setxattr(directoryURL.path!, SUAppleQuarantineIdentifier, quarantineData, quarantineDataLength, 0, XATTR_CREATE))
            XCTAssertGreaterThan(getxattr(directoryURL.path!, SUAppleQuarantineIdentifier, nil, 0, 0, XATTR_NOFOLLOW), 0)
            
            XCTAssertEqual(0, setxattr(fileInDirectoryURL.path!, SUAppleQuarantineIdentifier, quarantineData, quarantineDataLength, 0, XATTR_CREATE))
            XCTAssertGreaterThan(getxattr(fileInDirectoryURL.path!, SUAppleQuarantineIdentifier, nil, 0, 0, XATTR_NOFOLLOW), 0)
            
            try! fileManager.releaseItemFromQuarantineWithoutAuthenticationAtRootURL(directoryURL)
            
            XCTAssertEqual(-1, getxattr(directoryURL.path!, SUAppleQuarantineIdentifier, nil, 0, 0, XATTR_NOFOLLOW))
            XCTAssertEqual(-1, getxattr(fileInDirectoryURL.path!, SUAppleQuarantineIdentifier, nil, 0, 0, XATTR_NOFOLLOW))
        }
    }
    
    func groupIDAtPath(path: String) -> gid_t
    {
        let attributes = try! NSFileManager.defaultManager().attributesOfItemAtPath(path)
        let groupID = attributes[NSFileGroupOwnerAccountID] as! NSNumber
        return groupID.unsignedIntValue
    }
    
    // Only the super user can alter user IDs, so changing user IDs is not tested here
    // Instead we try to change the group ID - we just have to be a member of that group
    func testAlterFilesGroupID()
    {
        makeTempFiles() { fileManager, rootURL, ordinaryFileURL, directoryURL, fileInDirectoryURL in
            XCTAssertNil(try? fileManager.changeOwnerAndGroupOfItemAtRootURL(ordinaryFileURL, toMatchURL: rootURL.URLByAppendingPathComponent("does not exist")))
            
            XCTAssertNil(try? fileManager.changeOwnerAndGroupOfItemAtRootURL(rootURL.URLByAppendingPathComponent("does not exist"), toMatchURL: ordinaryFileURL))
            
            let everyoneGroup = getgrnam("everyone")
            let everyoneGroupID = everyoneGroup.memory.gr_gid
            
            let staffGroup = getgrnam("staff")
            let staffGroupID = staffGroup.memory.gr_gid
            
            XCTAssertNotEqual(staffGroupID, everyoneGroupID)
            
            XCTAssertEqual(staffGroupID, self.groupIDAtPath(ordinaryFileURL.path!))
            XCTAssertEqual(staffGroupID, self.groupIDAtPath(directoryURL.path!))
            XCTAssertEqual(staffGroupID, self.groupIDAtPath(fileInDirectoryURL.path!))
            
            try! fileManager.changeOwnerAndGroupOfItemAtRootURL(fileInDirectoryURL, toMatchURL: ordinaryFileURL)
            try! fileManager.changeOwnerAndGroupOfItemAtRootURL(ordinaryFileURL, toMatchURL: ordinaryFileURL)
            
            XCTAssertEqual(staffGroupID, self.groupIDAtPath(ordinaryFileURL.path!))
            XCTAssertEqual(staffGroupID, self.groupIDAtPath(directoryURL.path!))
            
            XCTAssertEqual(0, chown(ordinaryFileURL.path!, getuid(), everyoneGroupID))
            XCTAssertEqual(everyoneGroupID, self.groupIDAtPath(ordinaryFileURL.path!))
            
            try! fileManager.changeOwnerAndGroupOfItemAtRootURL(fileInDirectoryURL, toMatchURL: ordinaryFileURL)
            XCTAssertEqual(everyoneGroupID, self.groupIDAtPath(fileInDirectoryURL.path!))
            
            try! fileManager.changeOwnerAndGroupOfItemAtRootURL(fileInDirectoryURL, toMatchURL: directoryURL)
            XCTAssertEqual(staffGroupID, self.groupIDAtPath(fileInDirectoryURL.path!))
            
            try! fileManager.changeOwnerAndGroupOfItemAtRootURL(directoryURL, toMatchURL: ordinaryFileURL)
            XCTAssertEqual(everyoneGroupID, self.groupIDAtPath(directoryURL.path!))
            XCTAssertEqual(everyoneGroupID, self.groupIDAtPath(fileInDirectoryURL.path!))
        }
    }
    
    func testUpdateFileModificationTime()
    {
        makeTempFiles() { fileManager, rootURL, ordinaryFileURL, directoryURL, fileInDirectoryURL in
            XCTAssertNil(try? fileManager.updateModificationAndAccessTimeOfItemAtURL(rootURL.URLByAppendingPathComponent("does not exist")))
            
            let oldOrdinaryFileAttributes = try! NSFileManager.defaultManager().attributesOfItemAtPath(ordinaryFileURL.path!)
            let oldDirectoryAttributes = try! NSFileManager.defaultManager().attributesOfItemAtPath(directoryURL.path!)
            
            sleep(1); // wait for clock to advance
            
            try! fileManager.updateModificationAndAccessTimeOfItemAtURL(ordinaryFileURL)
            try! fileManager.updateModificationAndAccessTimeOfItemAtURL(directoryURL)
            
            let newOrdinaryFileAttributes = try! NSFileManager.defaultManager().attributesOfItemAtPath(ordinaryFileURL.path!)
            XCTAssertGreaterThan((newOrdinaryFileAttributes[NSFileModificationDate] as! NSDate).timeIntervalSinceDate(oldOrdinaryFileAttributes[NSFileModificationDate] as! NSDate), 0)
            
            let newDirectoryAttributes = try! NSFileManager.defaultManager().attributesOfItemAtPath(directoryURL.path!)
            XCTAssertGreaterThan((newDirectoryAttributes[NSFileModificationDate] as! NSDate).timeIntervalSinceDate(oldDirectoryAttributes[NSFileModificationDate] as! NSDate), 0)
        }
    }
    
    func testFileExists()
    {
        makeTempFiles() { fileManager, rootURL, ordinaryFileURL, directoryURL, fileInDirectoryURL in
            XCTAssertTrue(fileManager._itemExistsAtURL(ordinaryFileURL))
            XCTAssertTrue(fileManager._itemExistsAtURL(directoryURL))
            XCTAssertFalse(fileManager._itemExistsAtURL(rootURL.URLByAppendingPathComponent("does not exist")))
            
            var isOrdinaryFileDirectory: ObjCBool = false
            XCTAssertTrue(fileManager._itemExistsAtURL(ordinaryFileURL, isDirectory: &isOrdinaryFileDirectory) && !isOrdinaryFileDirectory)
            
            var isDirectoryADirectory: ObjCBool = false
            XCTAssertTrue(fileManager._itemExistsAtURL(directoryURL, isDirectory: &isDirectoryADirectory) && isDirectoryADirectory)
            
            XCTAssertFalse(fileManager._itemExistsAtURL(rootURL.URLByAppendingPathComponent("does not exist"), isDirectory: nil))
            
            let validSymlinkURL = rootURL.URLByAppendingPathComponent("symlink test")
            try! NSFileManager.defaultManager().createSymbolicLinkAtURL(validSymlinkURL, withDestinationURL: directoryURL)
            
            XCTAssertTrue(fileManager._itemExistsAtURL(validSymlinkURL))
            
            var validSymlinkIsADirectory: ObjCBool = false
            XCTAssertTrue(fileManager._itemExistsAtURL(validSymlinkURL, isDirectory: &validSymlinkIsADirectory) && !validSymlinkIsADirectory)
            
            let invalidSymlinkURL = rootURL.URLByAppendingPathComponent("symlink test 2")
            try! NSFileManager.defaultManager().createSymbolicLinkAtURL(invalidSymlinkURL, withDestinationURL: rootURL.URLByAppendingPathComponent("does not exist"))
            
            // Symlink should still exist even if it doesn't point to a file that exists
            XCTAssertTrue(fileManager._itemExistsAtURL(invalidSymlinkURL))
            
            var invalidSymlinkIsADirectory: ObjCBool = false
            XCTAssertTrue(fileManager._itemExistsAtURL(invalidSymlinkURL, isDirectory: &invalidSymlinkIsADirectory) && !invalidSymlinkIsADirectory)
        }
    }
    
    func testMakeDirectory()
    {
        makeTempFiles() { fileManager, rootURL, ordinaryFileURL, directoryURL, fileInDirectoryURL in
            XCTAssertNil(try? fileManager._makeDirectoryAtURL(ordinaryFileURL))
            XCTAssertNil(try? fileManager._makeDirectoryAtURL(directoryURL))
            
            XCTAssertNil(try? fileManager._makeDirectoryAtURL(rootURL.URLByAppendingPathComponent("this should").URLByAppendingPathComponent("be a failure")))
            
            let newDirectoryURL = rootURL.URLByAppendingPathComponent("new test directory")
            XCTAssertFalse(fileManager._itemExistsAtURL(newDirectoryURL))
            try! fileManager._makeDirectoryAtURL(newDirectoryURL)
            
            var isDirectory: ObjCBool = false
            XCTAssertTrue(fileManager._itemExistsAtURL(newDirectoryURL, isDirectory: &isDirectory))
        }
    }
    
    // This alone shouldn't prompt a password dialog and should always succeed
    func testAcquireAuthorization()
    {
        let fileManager = SUFileManager()
        try! fileManager._acquireAuthorization()
    }
}
