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

    func sha256String() -> String? {
        var context = CC_SHA256_CTX()
        CC_SHA256_Init(&context)

        while true {
            let data = self.readData(ofLength: 65_536)

            guard data.count > 0 else { break }

            let _ = data.withUnsafeBytes {
                CC_SHA256_Update(&context, $0.baseAddress, numericCast($0.count))
            }
        }

        let hash = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: Int(CC_SHA256_DIGEST_LENGTH))

        CC_SHA256_Final(hash.baseAddress, &context)

        return hash.reduce("") { $0 + String(format: "%02x", $1) }
    }

}

extension URL {

    func sha256String() -> String? {
        guard let filehandle = try? FileHandle(forReadingFrom: self) else { return nil }

        return filehandle.sha256String()
    }

}
