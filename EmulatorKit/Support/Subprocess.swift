import Foundation

/// Result of a finished subprocess.
public struct SubprocessResult: Sendable {
    public let status: Int32
    public let stdout: Data
    public let stderr: Data

    public var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
    public var stderrText: String { String(decoding: stderr, as: UTF8.self) }
}

/// Minimal async wrapper around `Process`. Stdout and stderr are drained
/// concurrently so large outputs (e.g. `dumpsys`) cannot deadlock the pipe.
public enum Subprocess {
    public static func run(
        _ executable: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil,
        stdin: Data? = nil
    ) async throws -> SubprocessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let inPipe: Pipe? = stdin.map { _ in Pipe() }
        if let inPipe { process.standardInput = inPipe }

        let outHandle = out.fileHandleForReading
        let errHandle = err.fileHandleForReading

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<SubprocessResult, Error>) in
                let group = DispatchGroup()
                let box = ResultBox()
                group.enter()
                DispatchQueue.global().async {
                    let d = outHandle.readDataToEndOfFile()
                    box.set(stdout: d)
                    group.leave()
                }
                group.enter()
                DispatchQueue.global().async {
                    let d = errHandle.readDataToEndOfFile()
                    box.set(stderr: d)
                    group.leave()
                }
                process.terminationHandler = { p in
                    group.notify(queue: .global()) {
                        cont.resume(returning: SubprocessResult(status: p.terminationStatus,
                                                                stdout: box.stdout, stderr: box.stderr))
                    }
                }
                do {
                    try process.run()
                    if let inPipe, let stdin {
                        inPipe.fileHandleForWriting.write(stdin)
                        try? inPipe.fileHandleForWriting.close()
                    }
                } catch {
                    cont.resume(throwing: error)
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }

    private final class ResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _stdout = Data(), _stderr = Data()
        var stdout: Data { lock.withLock { _stdout } }
        var stderr: Data { lock.withLock { _stderr } }
        func set(stdout: Data) { lock.withLock { _stdout = stdout } }
        func set(stderr: Data) { lock.withLock { _stderr = stderr } }
    }
}
