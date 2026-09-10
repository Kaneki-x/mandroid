import EmulatorKit
import SwiftUI
import UniformTypeIdentifiers

/// Lists installed third-party apps and opens them in windows.
struct LibraryView: View {
    @Bindable var coordinator: RunnerCoordinator
    let windows: WindowManager
    @State private var search = ""
    @State private var dropTargeted = false

    private var filtered: [String] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? coordinator.installedPackages : coordinator.installedPackages.filter { $0.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if coordinator.installedPackages.isEmpty {
                emptyState
            } else {
                List(filtered, id: \.self) { pkg in
                    HStack {
                        Image(systemName: "app.dashed").foregroundStyle(.secondary)
                        Text(pkg).font(.body.monospaced())
                        Spacer()
                        if coordinator.sessions[pkg] != nil {
                            Text("Open").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { windows.open(package: pkg) }
                    .contextMenu {
                        Button("Open") { windows.open(package: pkg) }
                        Button("Uninstall…", role: .destructive) { confirmUninstall(pkg) }
                    }
                }
                .listStyle(.inset)
            }
            Divider()
            HStack {
                Text("\(coordinator.sessions.count) of \(DisplaySlotPool.capacity) windows in use")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Refresh") { Task { await coordinator.refreshInstalledPackages() } }
                Button("Install APK…") { pickAPK() }
                Button("Play Store") {
                    Task { await coordinator.openPlayStore() }
                    windows.showDeviceScreen()
                }
                Button("Device Screen") { windows.showDeviceScreen() }
            }
            .padding(10)
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Filter packages")
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

    private func confirmUninstall(_ pkg: String) {
        let alert = NSAlert()
        alert.messageText = "Uninstall \(pkg)?"
        alert.informativeText = "The app and its data will be removed from the virtual device."
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            Task { do { try await coordinator.uninstall(package: pkg) } catch { windows.presentError(error, title: "Uninstall failed") } }
        }
    }
}
