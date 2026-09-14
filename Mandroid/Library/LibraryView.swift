import MandroidKit
import SwiftUI
import UniformTypeIdentifiers

/// Lists installed third-party apps with icons and opens them in windows.
struct LibraryView: View {
    @Bindable var coordinator: RunnerCoordinator
    let windows: WindowManager
    @State private var search = ""
    @State private var dropTargeted = false
    @State private var proxyApp: AppInfo?

    private var filtered: [AppInfo] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? coordinator.apps
            : coordinator.apps.filter { $0.label.lowercased().contains(q) || $0.package.lowercased().contains(q) }
    }

    private let columns = [GridItem(.adaptive(minimum: 96, maximum: 120), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            if let error = coordinator.proxyError {
                Text("HTTP proxy setup failed: \(error)").font(.callout).foregroundStyle(.red).padding(10)
            }
            if coordinator.apps.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(filtered) { app in
                            AppTile(app: app, isOpen: coordinator.sessions[app.package] != nil,
                                    isParked: coordinator.parked[app.package] != nil)
                                .onTapGesture(count: 2) { windows.open(package: app.package) }
                                .contextMenu {
                                    Button("Open") { windows.open(package: app.package) }
                                    if coordinator.sessions[app.package] != nil {
                                        Button("Close") {
                                            windows.appWindows[app.package]?.window?.performClose(nil)
                                        }
                                    }
                                    Button("HTTP Proxy…") { proxyApp = app }
                                    Divider()
                                    Button("Uninstall…", role: .destructive) { confirmUninstall(app) }
                                }
                        }
                    }
                    .padding(16)
                }
            }
            Divider()
            HStack {
                Text("\(coordinator.sessions.count) of \(DisplaySlotPool.capacity) windows in use")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Refresh") { Task { await coordinator.refreshApps() } }
                Button("Install APK…") { pickAPK() }
                Button("Play Store") {
                    Task { await coordinator.openPlayStore() }
                    windows.showDeviceScreen()
                }
                Button("Device Screen") { windows.showDeviceScreen() }
            }
            .padding(10)
        }
        .sheet(item: $proxyApp) { app in AppProxyView(app: app, coordinator: coordinator) }
        .searchable(text: $search, placement: .toolbar, prompt: "Search apps")
        .frame(minWidth: 460, minHeight: 320)
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.pathExtension.lowercased() == "apk" else { return }
                    Task { @MainActor in
                        do { try await coordinator.installAPK(url) } catch { windows.presentError(error, title: "Install failed") }
                    }
                }
            }
            return true
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 8).strokeBorder(.tint, lineWidth: 3).padding(4)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.and.arrow.down.on.square").font(.system(size: 36)).foregroundStyle(.secondary)
            Text("No apps installed yet").font(.title3)
            Text("Install apps from the Play Store on the device screen, or drop an APK here.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func pickAPK() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "apk") ?? .data]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            Task { do { try await coordinator.installAPK(url) } catch { windows.presentError(error, title: "Install failed") } }
        }
    }

    private func confirmUninstall(_ app: AppInfo) {
        let alert = NSAlert()
        alert.messageText = "Uninstall \(app.label)?"
        alert.informativeText = "\(app.package) and its data will be removed from the virtual device."
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            Task { do { try await coordinator.uninstall(package: app.package) } catch { windows.presentError(error, title: "Uninstall failed") } }
        }
    }
}

/// Icon + label tile. Falls back to a letter tile when no icon was extracted.
struct AppTile: View {
    let app: AppInfo
    let isOpen: Bool
    let isParked: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                AppIconView(app: app, size: 56)
                if isOpen || isParked {
                    Circle().fill(isOpen ? Color.green : Color.orange).frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
                        .offset(x: 2, y: 2)
                }
            }
            Text(app.label).font(.caption).lineLimit(2).multilineTextAlignment(.center)
                .frame(height: 30, alignment: .top)
        }
        .frame(width: 96)
        .padding(6)
        .contentShape(Rectangle())
        .help(app.package)
    }
}

struct AppIconView: View {
    let app: AppInfo
    let size: CGFloat

    var body: some View {
        Group {
            if let file = app.iconFile, let image = NSImage(contentsOf: file) {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.22).fill(color)
                    Text(String(app.label.prefix(1)).uppercased())
                        .font(.system(size: size * 0.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
    }

    private var color: Color {
        let hues: [Color] = [.blue, .indigo, .purple, .pink, .red, .orange, .teal, .green, .mint, .cyan]
        return hues[abs(app.package.hashValue) % hues.count]
    }
}
