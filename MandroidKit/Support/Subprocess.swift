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
        let lifecycle = ProcessLifecycle(process)
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

        let result = try await withTaskCancellationHandler {
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
                    try lifecycle.start()
                    if let inPipe, let stdin {
                        DispatchQueue.global().async {
                            try? inPipe.fileHandleForWriting.write(contentsOf: stdin)
                            try? inPipe.fileHandleForWriting.close()
                        }
                    }
                } catch {
                    try? out.fileHandleForWriting.close()
                    try? err.fileHandleForWriting.close()
                    try? inPipe?.fileHandleForWriting.close()
                    cont.resume(throwing: error)
                }
            }
        } onCancel: {
            lifecycle.cancel()
        }
        try Task.checkCancellation()
        return result
    }

    /// Serializes cancellation with launch so a pre-cancelled task cannot
    /// spawn an unowned process. Escalate when a child ignores SIGTERM.
    private final class ProcessLifecycle: @unchecked Sendable {
        private let lock = NSLock()
        private let process: Process
        private var cancelled = false
        init(_ process: Process) { self.process = process }
        func start() throws {
            try lock.withLock {
                if cancelled { throw CancellationError() }
                try process.run()
            }
        }
        func cancel() {
            lock.withLock {
                cancelled = true
                if process.isRunning { process.terminate() }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [self] in
                lock.withLock {
                    if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
                }
            }
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
