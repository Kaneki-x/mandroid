import MandroidKit
import SwiftUI
import UniformTypeIdentifiers

/// Lists installed third-party apps with icons and opens them in windows.
struct LibraryView: View {
    @Bindable var coordinator: RunnerCoordinator
    let windows: WindowManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var search = ""
    @State private var dropTargeted = false
    @State private var proxyApp: AppInfo?

    private var filtered: [AppInfo] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? coordinator.apps
            : coordinator.apps.filter { $0.label.lowercased().contains(q) || $0.package.lowercased().contains(q) }
    }

    private let columns = [GridItem(.adaptive(minimum: 112, maximum: 160), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            if let error = coordinator.proxyError {
                HostNotice(message: "HTTP proxy setup failed: \(error)").padding(16)
            }
            if coordinator.apps.isEmpty {
                emptyState
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: search)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(filtered) { app in
                            AppTile(app: app, isOpen: coordinator.sessions[app.package] != nil,
                                    isParked: coordinator.parked[app.package] != nil,
                                    open: { windows.open(package: app.package) })
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

            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItemGroup {
                Button(action: pickAPK) { Label("Install APK…", systemImage: "plus") }
                    .help("Install an APK from your Mac")
                Button { Task { await coordinator.refreshApps() } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }.help("Refresh installed apps")
                Menu {
                    Button("Play Store") {
                        Task { await coordinator.openPlayStore() }
                        windows.showDeviceScreen()
                    }
                    Button("Device Screen") { windows.showDeviceScreen() }
                } label: { Label("Device", systemImage: "iphone") }
                .help("Open Play Store or the device screen")
            }
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
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(.regularMaterial)
                    RoundedRectangle(cornerRadius: 8).strokeBorder(.tint, lineWidth: 2)
                    Label("Drop APK files to install", systemImage: "square.and.arrow.down")
                        .font(.title3.weight(.medium))
                }
                .padding(8).allowsHitTesting(false).transition(.opacity)
            }
        }
        .animation(HostStyle.motion(reduceMotion: reduceMotion), value: dropTargeted)
        .animation(HostStyle.motion(reduceMotion: reduceMotion), value: coordinator.proxyError != nil)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.and.arrow.down.on.square").font(.system(size: 36)).foregroundStyle(.secondary)
            Text("No apps installed yet").font(.title3.weight(.semibold))
            Text("Install apps from the Play Store on the device screen, or drop an APK here.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Install APK…", action: pickAPK)
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

    let open: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @FocusState private var focused: Bool

    private var status: String { isParked ? "Paused" : isOpen ? "Running" : "" }

    var body: some View {
        VStack(spacing: 8) {
            AppIconView(app: app, size: 56).accessibilityHidden(true)
            Text(app.label).font(.callout).lineLimit(2).multilineTextAlignment(.center)
                .frame(height: 36, alignment: .top)
            Label(status, systemImage: isParked ? "pause.circle.fill" : "circle.fill")
                .font(.caption2).foregroundStyle(.secondary)
                .opacity(status.isEmpty ? 0 : 1)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(hovering || focused ? Color.accentColor.opacity(0.1) : .clear,
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(focused ? Color.accentColor : .clear, lineWidth: 2) }
        .contentShape(Rectangle())
        .focusable().focused($focused).focusEffectDisabled()
        .onTapGesture(count: 2, perform: open)
        .onTapGesture { focused = true }
        .onKeyPress(.return) { open(); return .handled }
        .onKeyPress(.space) { open(); return .handled }
        .onHover { hovering = $0 }
        .animation(HostStyle.motion(reduceMotion: reduceMotion, hover: true), value: hovering)
        .animation(HostStyle.motion(reduceMotion: reduceMotion), value: status)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.label)
        .accessibilityValue(status.isEmpty ? "Installed" : status)
        .accessibilityHint("Open in an Android app window")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open() }
        .help("\(app.label)\n\(app.package)")
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
        return hues[Int(app.package.utf8.reduce(UInt(0)) { ($0 &* 31) &+ UInt($1) } % UInt(hues.count))]
    }
}
