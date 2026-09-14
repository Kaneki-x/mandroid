import Foundation
import GRPCCore
import SwiftProtobuf

public typealias PBDisplayConfiguration = Android_Emulation_Control_DisplayConfiguration
public typealias PBDisplayConfigurations = Android_Emulation_Control_DisplayConfigurations
public typealias PBImageFormat = Android_Emulation_Control_ImageFormat
public typealias PBImage = Android_Emulation_Control_Image
public typealias PBInputEvent = Android_Emulation_Control_InputEvent
public typealias PBTouch = Android_Emulation_Control_Touch
public typealias PBTouchEvent = Android_Emulation_Control_TouchEvent
public typealias PBKeyboardEvent = Android_Emulation_Control_KeyboardEvent
public typealias PBNotification = Android_Emulation_Control_Notification

/// Display flags used for every secondary display:
/// `PUBLIC | OWN_CONTENT_ONLY | SUPPORTS_TOUCH | ROTATES_WITH_CONTENT | TRUSTED`.
/// Never 0 (system bars) and never without TRUSTED (activities won't launch).
public let secondaryDisplayFlags: UInt32 = 1225

/// A secondary display request as we hand it to the emulator.
public struct DisplaySpec: Sendable, Hashable {
    public var index: Int      // 1…3
    public var width: Int
    public var height: Int
    public var dpi: Int
    public init(index: Int, width: Int, height: Int, dpi: Int) {
        self.index = index; self.width = width; self.height = height; self.dpi = dpi
    }
}

/// Typed facade over the generated client for the calls the runner needs.
public struct EmulatorClient: Sendable {
    public let connection: EmulatorConnection
    var controller: EmulatorControllerClient { connection.controller }

    public init(connection: EmulatorConnection) { self.connection = connection }

    private var commandOptions: CallOptions {
        var options = CallOptions.defaults
        options.timeout = .seconds(10)
        return options
    }

    public func status() async throws -> (version: String, booted: Bool, uptimeMs: Int64) {
        let s = try await controller.getStatus(Google_Protobuf_Empty())
        return (s.version, s.booted, Int64(s.uptime))
    }

    public func displays() async throws -> PBDisplayConfigurations {
        try await controller.getDisplayConfigurations(Google_Protobuf_Empty())
    }

    /// Pushes the **full** secondary set. Displays not listed are removed;
    /// an empty list removes all of them. Display 0 is implicit.
    @discardableResult
    public func setSecondaryDisplays(_ specs: [DisplaySpec]) async throws -> PBDisplayConfigurations {
        var req = PBDisplayConfigurations()
        for s in specs {
            var d = PBDisplayConfiguration()
            d.display = UInt32(s.index)
            d.width = UInt32(s.width)
            d.height = UInt32(s.height)
            d.dpi = UInt32(s.dpi)
            d.flags = secondaryDisplayFlags
            req.displays.append(d)
        }
        do {
            return try await controller.setDisplayConfigurations(req, options: commandOptions)
        } catch let e as RPCError {
            throw MandroidKitError.display("setDisplayConfigurations: \(e.code) \(e.message)")
        }
    }

    /// One RGBA8888 frame (server-side scaled). Throws `failedPrecondition`
    /// while the display has not rendered anything yet.
    public func screenshot(display: Int, width: Int, height: Int) async throws -> PBImage {
        var f = PBImageFormat()
        f.format = .rgba8888
        f.display = UInt32(display)
        f.width = UInt32(width)
        f.height = UInt32(height)
        return try await controller.getScreenshot(f, options: EmulatorConnection.largeMessageOptions)
    }

    public func sendKey(_ event: PBKeyboardEvent) async throws {
        _ = try await controller.sendKey(event)
    }

    public func sendTouch(_ event: PBTouchEvent) async throws {
        _ = try await controller.sendTouch(event)
    }

    public func setClipboard(_ text: String) async throws {
        var c = Android_Emulation_Control_ClipData()
        c.text = text
        _ = try await controller.setClipboard(c)
    }

    /// Asks QEMU to power off the guest; the process exits shortly after.
    public func requestShutdown() async throws {
        var s = Android_Emulation_Control_VmRunState()
        s.state = .shutdown
        _ = try await controller.setVmState(s, options: commandOptions)
    }
}
