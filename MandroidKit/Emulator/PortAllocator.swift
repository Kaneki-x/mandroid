import Darwin
import Foundation

/// Finds free TCP ports on loopback.
public enum PortAllocator {
    /// True if nothing is listening on `port` (bind succeeds).
    public static func isFree(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        // Do not enable address reuse: a wildcard gRPC listener may itself
        // allow reuse, making a second bind appear to be a free port.
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr = in_addr(s_addr: INADDR_ANY)
        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        return r == 0
    }

    /// Emulator console ports must be even and in 5554…5682; adb port is +1.
    public static func freeConsolePort() -> Int? {
        for p in stride(from: 5554, through: 5682, by: 2) where isFree(p) && isFree(p + 1) { return p }
        return nil
    }

    public static func freePort(in range: ClosedRange<Int>) -> Int? {
        range.first(where: isFree)
    }
}
