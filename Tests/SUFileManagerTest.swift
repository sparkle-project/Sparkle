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
    func makeTempFiles(_ testBlock: (SUFileManager, URL, URL, URL, URL, URL, URL) -> Void)
    {
        let fileManager = SUFileManager()
        
        let tempDirectoryURL = try! fileManager.makeTemporaryDirectoryAppropriate(forDirectoryURL: URL(fileURLWithPath: NSHomeDirectory()))

        defer {
            try! fileManager.removeItem(at: tempDirectoryURL)
        }

        let ordinaryFileURL = tempDirectoryURL.appendingPathComponent("a file written by sparkles unit tests")
        try! "foo".data(using: String.Encoding.utf8)!.write(to: ordinaryFileURL, options: .atomic)

        let directoryURL = tempDirectoryURL.appendingPathComponent("a directory written by sparkles unit tests")
        try! FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: false, attributes: nil)

        let fileInDirectoryURL = directoryURL.appendingPathComponent("a file inside a directory written by sparkles unit tests")
        try! "bar baz".data(using: String.Encoding.utf8)!.write(to: fileInDirectoryURL, options: .atomic)

        let validSymlinkURL = tempDirectoryURL.appendingPathComponent("symlink test")
        try! FileManager.default.createSymbolicLink(at: validSymlinkURL, withDestinationURL: directoryURL)

        let invalidSymlinkURL = tempDirectoryURL.appendingPathComponent("symlink test 2")
        try! FileManager.default.createSymbolicLink(at: invalidSymlinkURL, withDestinationURL: (tempDirectoryURL.appendingPathComponent("does not exist")))

        testBlock(fileManager, tempDirectoryURL, ordinaryFileURL, directoryURL, fileInDirectoryURL, validSymlinkURL, invalidSymlinkURL)
    }

    func testMoveFiles()
    {
        makeTempFiles() { fileManager, rootURL, ordinaryFileURL, directoryURL, fileInDirectoryURL, validSymlinkURL, invalidSymlinkURL in
            XCTAssertNil(try? fileManager.moveItem(at: ordinaryFileURL, to: directoryURL))
            XCTAssertNil(try? fileManager.moveItem(at: ordinaryFileURL, to: directoryURL.appendingPathComponent("foo").appendingPathComponent("bar")))
            XCTAssertNil(try? fileManager.moveItem(at: rootURL.appendingPathComponent("does not exist"), to: directoryURL))

            let newFileURL = (ordinaryFileURL.deletingLastPathComponent().appendingPathComponent("new file"))
            try! fileManager.moveItem(at: ordinaryFileURL, to: newFileURL)
            XCTAssertFalse(fileManager._itemExists(at: ordinaryFileURL))
            XCTAssertTrue(fileManager._itemExists(at: newFileURL))

            let newValidSymlinkURL = (ordinaryFileURL.deletingLastPathComponent().appendingPathComponent("new symlink"))
            try! fileManager.moveItem(at: validSymlinkURL, to: newValidSymlinkURL)
            XCTAssertFalse(fileManager._itemExists(at: validSymlinkURL))
            XCTAssertTrue(fileManager._itemExists(at: newValidSymlinkURL))
            XCTAssertTrue(fileManager._itemExists(at: directoryURL))

            let newInvalidSymlinkURL = (ordinaryFileURL.deletingLastPathComponent().appendingPathComponent("new invalid symlink"))
            try! fileManager.moveItem(at: invalidSymlinkURL, to: newInvalidSymlinkURL)
            XCTAssertFalse(fileManager._itemExists(at: invalidSymlinkURL))
            XCTAssertTrue(fileManager._itemExists(at: newValidSymlinkURL))

            let newDirectoryURL = (ordinaryFileURL.deletingLastPathComponent().appendingPathComponent("new directory"))
            try! fileManager.moveItem(at: directoryURL, to: newDirectoryURL)
            XCTAssertFalse(fileManager._itemExists(at: directoryURL))
            XCTAssertTrue(fileManager._itemExists(at: newDirectoryURL))
            XCTAssertFalse(fileManager._itemExists(at: fileInDirectoryURL))
            XCTAssertTrue(fileManager._itemExists(at: newDirectoryURL.appendingPathComponent(fileInDirectoryURL.lastPathComponent)))
        }
    }

    func testCopyFiles()
    {
        makeTempFiles() { fileManager, rootURL, ordinaryFileURL, directoryURL, fileInDirectoryURL, _, invalidSymlinkURL in
            XCTAssertNil(try? fileManager.copyItem(at: ordinaryFileURL, to: directoryURL))
            XCTAssertNil(try? fileManager.copyItem(at: ordinaryFileURL, to: directoryURL.appendingPathComponent("foo").appendingPathComponent("bar")))
            XCTAssertNil(try? fileManager.copyItem(at: rootURL.appendingPathComponent("does not exist"), to: directoryURL))

            let newFileURL = (ordinaryFileURL.deletingLastPathComponent().appendingPathComponent("new file"))
            try! fileManager.copyItem(at: ordinaryFileURL, to: newFileURL)
            XCTAssertTrue(fileManager._itemExists(at: ordinaryFileURL))
            XCTAssertTrue(fileManager._itemExists(at: newFileURL))

            let newSymlinkURL = (ordinaryFileURL.deletingLastPathComponent().appendingPathComponent("new symlink file"))
            try! fileManager.copyItem(at: invalidSymlinkURL, to: newSymlinkURL)
            XCTAssertTrue(fileManager._itemExists(at: newSymlinkURL))

            let newDirectoryURL = (ordinaryFileURL.deletingLastPathComponent().appendingPathComponent("new directory"))
            try! fileManager.copyItem(at: directoryURL, to: newDirectoryURL)
            XCTAssertTrue(fileManager._itemExists(at: directoryURL))
            XCTAssertTrue(fileManager._itemExists(at: newDirectoryURL))
            XCTAssertTrue(fileManager._itemExists(at: fileInDirectoryURL))
            XCTAssertTrue(fileManager._itemExists(at: newDirectoryURL.appendingPathComponent(fileInDirectoryURL.lastPathComponent)))
        }
    }

    func testRemoveFiles()
    {
        makeTempFiles() { fileManager, rootURL, ordinaryFileURL, directoryURL, fileInDirectoryURL, validSymlinkURL, _ in
            XCTAssertNil(try? fileManager.removeItem(at: rootURL.appendingPathComponent("does not exist")))

            try! fileManager.removeItem(at: ordinaryFileURL)
            XCTAssertFalse(fileManager._itemExists(at: ordinaryFileURL))

            try! fileManager.removeItem(at: validSymlinkURL)
            XCTAssertFalse(fileManager._itemExists(at: validSymlinkURL))
            XCTAssertTrue(fileManager._itemExists(at: directoryURL))

            try! fileManager.removeItem(at: directoryURL)
            XCTAssertFalse(fileManager._itemExists(at: directoryURL))
            XCTAssertFalse(fileManager._itemExists(at: fileInDirectoryURL))
        }
    }

    func testReleaseFilesFromQuarantine()
    {
        makeTempFiles() { fileManager, _, ordinaryFileURL, directoryURL, fileInDirectoryURL, validSymlinkURL, _ in
            try! fileManager.releaseItemFromQuarantine(atRootURL: ordinaryFileURL)
            try! fileManager.releaseItemFromQuarantine(atRootURL: directoryURL)
            try! fileManager.releaseItemFromQuarantine(atRootURL: validSymlinkURL)

            let quarantineData = "does not really matter what is here".cString(using: String.Encoding.utf8)!
            let quarantineDataLength = Int(strlen(quarantineData))

            XCTAssertEqual(0, setxattr(ordinaryFileURL.path, SUAppleQuarantineIdentifier, quarantineData, quarantineDataLength, 0, XATTR_CREATE))
            XCTAssertGreaterThan(getxattr(ordinaryFileURL.path, SUAppleQuarantineIdentifier, nil, 0, 0, XATTR_NOFOLLOW), 0)

            try! fileManager.releaseItemFromQuarantine(atRootURL: ordinaryFileURL)
            XCTAssertEqual(-1, getxattr(ordinaryFileURL.path, SUAppleQuarantineIdentifier, nil, 0, 0, XATTR_NOFOLLOW))

            XCTAssertEqual(0, setxattr(directoryURL.path, SUAppleQuarantineIdentifier, quarantineData, quarantineDataLength, 0, XATTR_CREATE))
            XCTAssertGreaterThan(getxattr(directoryURL.path, SUAppleQuarantineIdentifier, nil, 0, 0, XATTR_NOFOLLOW), 0)

            XCTAssertEqual(0, setxattr(fileInDirectoryURL.path, SUAppleQuarantineIdentifier, quarantineData, quarantineDataLength, 0, XATTR_CREATE))
            XCTAssertGreaterThan(getxattr(fileInDirectoryURL.path, SUAppleQuarantineIdentifier, nil, 0, 0, XATTR_NOFOLLOW), 0)

            // Extended attributes can't be set on symbolic links currently
            try! fileManager.releaseItemFromQuarantine(atRootURL: validSymlinkURL)
            XCTAssertGreaterThan(getxattr(directoryURL.path, SUAppleQuarantineIdentifier, nil, 0, 0, XATTR_NOFOLLOW), 0)
            XCTAssertEqual(-1, getxattr(validSymlinkURL.path, SUAppleQuarantineIdentifier, nil, 0, 0, XATTR_NOFOLLOW))

            try! fileManager.releaseItemFromQuarantine(atRootURL: directoryURL)

            XCTAssertEqual(-1, getxattr(directoryURL.path, SUAppleQuarantineIdentifier, nil, 0, 0, XATTR_NOFOLLOW))
            XCTAssertEqual(-1, getxattr(fileInDirectoryURL.path, SUAppleQuarantineIdentifier, nil, 0, 0, XATTR_NOFOLLOW))
        }
    }

    func groupIDAtPath(_ path: String) -> gid_t
    {
        let attributes = try! FileManager.default.attributesOfItem(atPath: path)
        let groupID = attributes[FileAttributeKey.groupOwnerAccountID] as! NSNumber
        return groupID.uint32Value
    }

    // Only the super user can alter user IDs, so changing user IDs is not tested here
    // Instead we try to change the group ID - we just have to be a member of that group
    func testAlterFilesGroupID()
    {
        makeTempFiles() { fileManager, rootURL, ordinaryFileURL, directoryURL, fileInDirectoryURL, validSymlinkURL, _ in
            XCTAssertNil(try? fileManager.changeOwnerAndGroupOfItem(atRootURL: ordinaryFileURL, toMatch: rootURL.appendingPathComponent("does not exist")))

            XCTAssertNil(try? fileManager.changeOwnerAndGroupOfItem(atRootURL: rootURL.appendingPathComponent("does not exist"), toMatch: ordinaryFileURL))

            let everyoneGroup = getgrnam("everyone")
            let everyoneGroupID = everyoneGroup?.pointee.gr_gid

            let staffGroup = getgrnam("staff")
            let staffGroupID = staffGroup?.pointee.gr_gid

            XCTAssertNotEqual(staffGroupID, everyoneGroupID)

            XCTAssertEqual(staffGroupID, self.groupIDAtPath(ordinaryFileURL.path))
            XCTAssertEqual(staffGroupID, self.groupIDAtPath(directoryURL.path))
            XCTAssertEqual(staffGroupID, self.groupIDAtPath(fileInDirectoryURL.path))
            XCTAssertEqual(staffGroupID, self.groupIDAtPath(validSymlinkURL.path))

            try! fileManager.changeOwnerAndGroupOfItem(atRootURL: fileInDirectoryURL, toMatch: ordinaryFileURL)
            try! fileManager.changeOwnerAndGroupOfItem(atRootURL: ordinaryFileURL, toMatch: ordinaryFileURL)
            try! fileManager.changeOwnerAndGroupOfItem(atRootURL: validSymlinkURL, toMatch: ordinaryFileURL)

            XCTAssertEqual(staffGroupID, self.groupIDAtPath(ordinaryFileURL.path))
            XCTAssertEqual(staffGroupID, self.groupIDAtPath(directoryURL.path))
            XCTAssertEqual(staffGroupID, self.groupIDAtPath(validSymlinkURL.path))

            XCTAssertEqual(0, chown(ordinaryFileURL.path, getuid(), everyoneGroupID!))
            XCTAssertEqual(everyoneGroupID, self.groupIDAtPath(ordinaryFileURL.path))

            try! fileManager.changeOwnerAndGroupOfItem(atRootURL: fileInDirectoryURL, toMatch: ordinaryFileURL)
            XCTAssertEqual(everyoneGroupID, self.groupIDAtPath(fileInDirectoryURL.path))

            try! fileManager.changeOwnerAndGroupOfItem(atRootURL: fileInDirectoryURL, toMatch: directoryURL)
            XCTAssertEqual(staffGroupID, self.groupIDAtPath(fileInDirectoryURL.path))

            try! fileManager.changeOwnerAndGroupOfItem(atRootURL: validSymlinkURL, toMatch: ordinaryFileURL)
            XCTAssertEqual(everyoneGroupID, self.groupIDAtPath(validSymlinkURL.path))

            try! fileManager.changeOwnerAndGroupOfItem(atRootURL: directoryURL, toMatch: ordinaryFileURL)
            XCTAssertEqual(everyoneGroupID, self.groupIDAtPath(directoryURL.path))
            XCTAssertEqual(everyoneGroupID, self.groupIDAtPath(fileInDirectoryURL.path))
        }
    }

    func testUpdateFileModificationTime()
    {
        makeTempFiles() { fileManager, rootURL, ordinaryFileURL, directoryURL, _, validSymlinkURL, _ in
            XCTAssertNil(try? fileManager.updateModificationAndAccessTimeOfItem(at: rootURL.appendingPathComponent("does not exist")))

            let oldOrdinaryFileAttributes = try! FileManager.default.attributesOfItem(atPath: ordinaryFileURL.path)
            let oldDirectoryAttributes = try! FileManager.default.attributesOfItem(atPath: directoryURL.path)
            let oldValidSymlinkAttributes = try! FileManager.default.attributesOfItem(atPath: validSymlinkURL.path)

            sleep(1); // wait for clock to advance

            try! fileManager.updateModificationAndAccessTimeOfItem(at: ordinaryFileURL)
            try! fileManager.updateModificationAndAccessTimeOfItem(at: directoryURL)
            try! fileManager.updateModificationAndAccessTimeOfItem(at: validSymlinkURL)

            let newOrdinaryFileAttributes = try! FileManager.default.attributesOfItem(atPath: ordinaryFileURL.path)
            XCTAssertGreaterThan((newOrdinaryFileAttributes[FileAttributeKey.modificationDate] as! Date).timeIntervalSince(oldOrdinaryFileAttributes[FileAttributeKey.modificationDate] as! Date), 0)

            let newDirectoryAttributes = try! FileManager.default.attributesOfItem(atPath: directoryURL.path)
            XCTAssertGreaterThan((newDirectoryAttributes[FileAttributeKey.modificationDate] as! Date).timeIntervalSince(oldDirectoryAttributes[FileAttributeKey.modificationDate] as! Date), 0)

            let newSymlinkAttributes = try! FileManager.default.attributesOfItem(atPath: validSymlinkURL.path)
            XCTAssertGreaterThan((newSymlinkAttributes[FileAttributeKey.modificationDate] as! Date).timeIntervalSince(oldValidSymlinkAttributes[FileAttributeKey.modificationDate] as! Date), 0)
        }
    }

    func testUpdateFileAccessTime()
    {
        let accessTime: ((URL) -> timespec?) = { url in
            var outputStat = stat()
            let result = lstat(url.path, &outputStat)
            if result != 0 {
                return nil
            } else {
                return outputStat.st_atimespec
            }
        }

        let timespecEqual: (timespec, timespec) -> Bool = {t1, t2 in
            (t1.tv_sec == t2.tv_sec && t1.tv_nsec == t2.tv_nsec)
        }

        makeTempFiles() { fileManager, rootURL, ordinaryFileURL, directoryURL, fileInDirectoryURL, validSymlinkURL, _ in
            XCTAssertNil(try? fileManager.updateAccessTimeOfItem(atRootURL: rootURL.appendingPathComponent("does not exist")))

            let oldOrdinaryFileTime = accessTime(ordinaryFileURL)!
            let oldDirectoryTime = accessTime(directoryURL)!
            let oldValidSymlinkTime = accessTime(validSymlinkURL)!

            sleep(1); // wait for clock to advance

            // Make sure access time haven't changed since; lstat() shouldn't have changed the access time..
            XCTAssertTrue(timespecEqual(oldOrdinaryFileTime, accessTime(ordinaryFileURL)!))
            XCTAssertTrue(timespecEqual(oldDirectoryTime, accessTime(directoryURL)!))
            XCTAssertTrue(timespecEqual(oldValidSymlinkTime, accessTime(validSymlinkURL)!))

            // Test the symlink and make sure the target directory doesn't change
            try! fileManager.updateAccessTimeOfItem(atRootURL: validSymlinkURL)
            XCTAssertFalse(timespecEqual(oldValidSymlinkTime, accessTime(validSymlinkURL)!))
            XCTAssertTrue(timespecEqual(oldDirectoryTime, accessTime(directoryURL)!))

            // Test an ordinary file
            try! fileManager.updateAccessTimeOfItem(atRootURL: ordinaryFileURL)
            XCTAssertFalse(timespecEqual(oldOrdinaryFileTime, accessTime(ordinaryFileURL)!))

            // Test the directory and file inside the directory
            try! fileManager.updateAccessTimeOfItem(atRootURL: directoryURL)
            let newDirectoryTime = accessTime(directoryURL)!
            XCTAssertFalse(timespecEqual(oldDirectoryTime, newDirectoryTime))
            XCTAssertTrue(timespecEqual(newDirectoryTime, accessTime(fileInDirectoryURL)!))
        }
    }

    func testFileExists()
    {
        makeTempFiles() { fileManager, rootURL, ordinaryFileURL, directoryURL, _, validSymlinkURL, invalidSymlinkURL in
            XCTAssertTrue(fileManager._itemExists(at: ordinaryFileURL))
            XCTAssertTrue(fileManager._itemExists(at: directoryURL))
            XCTAssertFalse(fileManager._itemExists(at: rootURL.appendingPathComponent("does not exist")))

            var isOrdinaryFileDirectory: ObjCBool = false
            XCTAssertTrue(fileManager._itemExists(at: ordinaryFileURL, isDirectory: &isOrdinaryFileDirectory) && !isOrdinaryFileDirectory.boolValue)

            var isDirectoryADirectory: ObjCBool = false
            XCTAssertTrue(fileManager._itemExists(at: directoryURL, isDirectory: &isDirectoryADirectory) && isDirectoryADirectory.boolValue)

            XCTAssertFalse(fileManager._itemExists(at: rootURL.appendingPathComponent("does not exist"), isDirectory: nil))

            XCTAssertTrue(fileManager._itemExists(at: validSymlinkURL))

            var validSymlinkIsADirectory: ObjCBool = false
            XCTAssertTrue(fileManager._itemExists(at: validSymlinkURL, isDirectory: &validSymlinkIsADirectory) && !validSymlinkIsADirectory.boolValue)

            // Symlink should still exist even if it doesn't point to a file that exists
            XCTAssertTrue(fileManager._itemExists(at: invalidSymlinkURL))

            var invalidSymlinkIsADirectory: ObjCBool = false
            XCTAssertTrue(fileManager._itemExists(at: invalidSymlinkURL, isDirectory: &invalidSymlinkIsADirectory) && !invalidSymlinkIsADirectory.boolValue)
        }
    }

    func testMakeDirectory()
    {
        makeTempFiles() { fileManager, rootURL, ordinaryFileURL, directoryURL, _, validSymlinkURL, _ in
            XCTAssertNil(try? fileManager.makeDirectory(at: ordinaryFileURL))
            XCTAssertNil(try? fileManager.makeDirectory(at: directoryURL))

            XCTAssertNil(try? fileManager.makeDirectory(at: rootURL.appendingPathComponent("this should").appendingPathComponent("be a failure")))

            let newDirectoryURL = rootURL.appendingPathComponent("new test directory")
            XCTAssertFalse(fileManager._itemExists(at: newDirectoryURL))
            try! fileManager.makeDirectory(at: newDirectoryURL)

            var isDirectory: ObjCBool = false
            XCTAssertTrue(fileManager._itemExists(at: newDirectoryURL, isDirectory: &isDirectory))

            try! fileManager.removeItem(at: directoryURL)
            XCTAssertNil(try? fileManager.makeDirectory(at: validSymlinkURL))
        }
    }
}
