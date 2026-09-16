import AppKit
import SwiftUI

/// Shared native host presentation. Guest surfaces never inherit these styles.
enum HostStyle {
    static let spacing: CGFloat = 8
    static let inset: CGFloat = 24
    static func motion(reduceMotion: Bool, hover: Bool = false) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: hover ? 0.12 : 0.2)
    }

    @MainActor static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}

struct HostNotice: View {
    let message: String
    var symbol = "exclamationmark.triangle.fill"

    var body: some View {
        Label {
            Text(message).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.secondary)
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}
