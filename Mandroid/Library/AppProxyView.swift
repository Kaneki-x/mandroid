import SwiftUI
import MandroidKit

struct AppProxyView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let app: AppInfo
    @Bindable var coordinator: RunnerCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var enabled: Bool
    @State private var host: String
    @State private var port: String
    @State private var saving = false
    @State private var error: String?

    init(app: AppInfo, coordinator: RunnerCoordinator) {
        self.app = app
        self.coordinator = coordinator
        let endpoint = coordinator.appProxies[app.package]
        _enabled = State(initialValue: endpoint != nil)
        _host = State(initialValue: endpoint?.host ?? "localhost")
        _port = State(initialValue: endpoint.map { String($0.port) } ?? "8080")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                AppIconView(app: app, size: 40)
                VStack(alignment: .leading) {
                    Text("HTTP Proxy").font(.title2.bold())
                    Text(app.label).foregroundStyle(.secondary)
                }
            }
            Toggle("Use an HTTP proxy for this app", isOn: $enabled).disabled(saving)
            Form {
                TextField("Host", text: $host, prompt: Text("localhost"))
                TextField("Port", text: $port, prompt: Text("8080"))
            }
            .textFieldStyle(.roundedBorder)
            .disabled(!enabled || saving)
            Text("Use localhost for a proxy on this Mac. Each app can use a different proxy at the same time.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Applies to apps that honor Android HTTP proxy settings. Other traffic remains direct. Uses Android’s VPN connection and replaces another Android VPN if one is active.")
                .font(.caption).foregroundStyle(.secondary)
            if let error { HostNotice(message: error).transition(.opacity) }
            Divider()
            HStack {
                if saving {
                    ProgressView().controlSize(.small)
                    Text("Saving…").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(saving)
                Button("Save") { save() }.keyboardShortcut(.defaultAction).disabled(saving)
            }
        }
        .padding(HostStyle.inset).frame(width: 440)
        .animation(HostStyle.motion(reduceMotion: reduceMotion), value: error != nil)
        .animation(HostStyle.motion(reduceMotion: reduceMotion), value: saving)
        .interactiveDismissDisabled(saving)
    }

    private func save() {
        saving = true
        error = nil
        Task {
            do {
                let endpoint: HTTPProxyEndpoint?
                if enabled {
                    guard let value = Int(port.trimmingCharacters(in: .whitespaces)) else {
                        throw MandroidKitError.adb("Enter a port from 1 to 65535.")
                    }
                    endpoint = try HTTPProxyEndpoint(host: host, port: value)
                } else { endpoint = nil }
                try await coordinator.setHTTPProxy(endpoint, for: app.package)
                dismiss()
            } catch { self.error = error.localizedDescription }
            saving = false
        }
    }
}
