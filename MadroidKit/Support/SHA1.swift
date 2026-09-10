import CryptoKit
import Foundation

/// SHA-1 helpers. The SDK repository publishes SHA-1 checksums and the
/// `licenses/` files contain SHA-1 hashes of the license text, so this is
/// integrity matching against Google's manifest, not a security primitive.
public enum SHA1 {
    public static func hex(of data: Data) -> String {
        Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Streams a file through SHA-1 in 1 MiB chunks.
    public static func hex(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = Insecure.SHA1()
        while true {
            let chunk = try handle.read(upToCount: 1 << 20) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
