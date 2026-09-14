import Foundation

/// Progress of one download.
public struct DownloadProgress: Sendable, Equatable {
    public var received: Int64
    public var total: Int64?
    public var fraction: Double? { total.map { $0 > 0 ? Double(received) / Double($0) : 0 } }
}

/// Resumable HTTP downloader writing to `<destination>.part`, verifying SHA-1
/// and renaming atomically on success. Resume uses `Range:` against the
/// existing partial file; servers that ignore ranges restart from zero.
public actor Downloader {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Downloads `url` to `destination`. If `destination` already exists and
    /// matches `sha1`, returns immediately.
    public func download(
        _ url: URL,
        to destination: URL,
        expectedSize: Int64?,
        sha1: String?,
        progress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws {
        try Task.checkCancellation()
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            if let sha1, (try? SHA1.hex(ofFileAt: destination)) == sha1 {
                progress(DownloadProgress(received: expectedSize ?? 0, total: expectedSize))
                return
            }
            try? fm.removeItem(at: destination)
        }
        let part = destination.appendingPathExtension("part")
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        var attempt = 0
        while true {
            attempt += 1
            do {
                try await fetch(url, part: part, expectedSize: expectedSize, progress: progress)
                break
            } catch let e as URLError where attempt < 5 && e.code != .cancelled {
                Log.sdk.warning("download \(url.lastPathComponent) attempt \(attempt) failed: \(e.localizedDescription); retrying")
                try await Task.sleep(for: .seconds(Double(attempt) * 2))
            }
        }

        if let sha1 {
            let actual = try SHA1.hex(ofFileAt: part)
            guard actual == sha1 else {
                try? fm.removeItem(at: part)
                throw MadroidKitError.checksumMismatch(expected: sha1, actual: actual, file: destination.lastPathComponent)
            }
        }
        _ = try fm.replaceItemAt(destination, withItemAt: part)
    }

    private func fetch(_ url: URL, part: URL, expectedSize: Int64?,
                       progress: @escaping @Sendable (DownloadProgress) -> Void) async throws {
        let fm = FileManager.default
        var existing: Int64 = 0
        if let attrs = try? fm.attributesOfItem(atPath: part.path), let size = attrs[.size] as? Int64 {
            existing = size
        }
        if let expectedSize, existing > expectedSize { try? fm.removeItem(at: part); existing = 0 }
        if let expectedSize, existing == expectedSize, expectedSize > 0 {
            progress(DownloadProgress(received: existing, total: expectedSize))
            return
        }
        if !fm.fileExists(atPath: part.path) { fm.createFile(atPath: part.path, contents: nil) }

        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        if existing > 0 { request.setValue("bytes=\(existing)-", forHTTPHeaderField: "Range") }

        let handle = try FileHandle(forWritingTo: part)
        defer { try? handle.close() }

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw MadroidKitError.download("no HTTP response") }
        var received: Int64
        var rangeTotal: Int64?
        switch http.statusCode {
        case 206:
            guard let range = http.value(forHTTPHeaderField: "Content-Range"),
                  range.hasPrefix("bytes "),
                  let slash = range.firstIndex(of: "/"),
                  let total = Int64(range[range.index(after: slash)...]),
                  let dash = range[..<slash].firstIndex(of: "-"),
                  let start = Int64(range[range.index(range.startIndex, offsetBy: 6)..<dash]),
                  let end = Int64(range[range.index(after: dash)..<slash]),
                  start == existing, end >= start, total > end else {
                throw MadroidKitError.download("invalid resume range for \(url.lastPathComponent)")
            }
            rangeTotal = total
            try handle.seekToEnd(); received = existing
        case 200:
            try handle.truncate(atOffset: 0); received = 0
        default:
            throw MadroidKitError.download("HTTP \(http.statusCode) for \(url.lastPathComponent)")
        }
        let total: Int64? = expectedSize ?? rangeTotal ?? (http.expectedContentLength >= 0 ? http.expectedContentLength : nil)

        var buffer = Data(); buffer.reserveCapacity(1 << 20)
        var lastReport = Date.distantPast
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= (1 << 20) {
                try handle.write(contentsOf: buffer)
                received += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                let now = Date()
                if now.timeIntervalSince(lastReport) > 0.2 {
                    lastReport = now
                    progress(DownloadProgress(received: received, total: total))
                }
            }
            if Task.isCancelled { throw CancellationError() }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            received += Int64(buffer.count)
        }
        if let total, received != total {
            throw MadroidKitError.download("incomplete download: expected \(total) bytes, received \(received)")
        }
        progress(DownloadProgress(received: received, total: total ?? received))
    }
}
