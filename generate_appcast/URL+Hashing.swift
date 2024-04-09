//
//  URL+Hashing.swift
//  generate_appcast
//
//  Created by Nate Weaver on 2020-05-01.
//  Copyright © 2020 Sparkle Project. All rights reserved.
//

import Foundation
import CommonCrypto

extension FileHandle {

    /// Calculate the SHA-256 hash of the file referenced by the file handle.
    ///
    /// - Returns: The SHA-256 hash of the file (as a hexadecimal string).
    func sha256String() -> String {
        // This uses CommonCrypto instead of CryptoKit so it can work on macOS < 10.15
        var context = CC_SHA256_CTX()
        CC_SHA256_Init(&context)

        while true {
            let data = self.readData(ofLength: 65_536)

            guard data.count > 0 else { break }

            _ = data.withUnsafeBytes {
                CC_SHA256_Update(&context, $0.baseAddress, numericCast($0.count))
            }
        }

        let hash = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: Int(CC_SHA256_DIGEST_LENGTH))

        CC_SHA256_Final(hash.baseAddress, &context)

        defer {
            hash.deallocate()
        }
        
        return hash.reduce("") { $0 + String(format: "%02x", $1) }
    }

}

extension URL {

    /// Calculates the SHA-256 hash of the file referenced by the URL.
    ///
    /// - Returns: The SHA-256 hash of the file (as a hexadecimal string), or `nil` if
    ///   the URL doesn't point to a file.
    func sha256String() -> String? {
        guard self.isFileURL else { return nil }
        guard let filehandle = try? FileHandle(forReadingFrom: self) else { return nil }

        return filehandle.sha256String()
    }

}
