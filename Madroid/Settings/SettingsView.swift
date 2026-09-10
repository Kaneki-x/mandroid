import MadroidKit
import SwiftUI

struct SettingsView: View {
    let coordinator: RunnerCoordinator
    let windows: WindowManager
    @State private var settings = RunnerSettings.load()
    @State private var saved = RunnerSettings.load()

    private var needsRestart: Bool { settings.ramMB != saved.ramMB || settings.cores != saved.cores }

    var body: some View {
        Form {
            Section("Virtual device") {
                Picker("Memory", selection: $settings.ramMB) {
                    ForEach(RunnerSettings.ramChoices, id: \.self) { Text("\($0 / 1024) GB").tag($0) }
                }
                Picker("CPU cores", selection: $settings.cores) {
                    ForEach(RunnerSettings.coreChoices, id: \.self) { Text("\($0)").tag($0) }
                }
                if needsRestart {
                    Text("Takes effect after the emulator restarts.").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Restart Emulator") { restart(cold: false) }
                    Button("Cold Boot") { restart(cold: true) }
                }
            }
            Section("Windows") {
                Picker("New windows open", selection: $settings.landscapeByDefault) {
                    Text("Landscape").tag(true)
                    Text("Portrait").tag(false)
                }
                .pickerStyle(.segmented)
                Stepper("Default window height: \(settings.defaultWindowHeight) pt",
                        value: $settings.defaultWindowHeight, in: 500...1600, step: 50)
                Toggle("Create launcher stubs in ~/Applications/Android Apps", isOn: $settings.launcherStubs)
                Text("Stubs let Android apps appear in Spotlight and the Dock.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Downloads") {
                Picker("Download SDK from", selection: $settings.downloadMirror) {
                    Text("Automatic").tag(DownloadMirror.Preference.auto)
                    Text(DownloadMirror.google.name).tag(DownloadMirror.Preference.google)
                    Text(DownloadMirror.china.name).tag(DownloadMirror.Preference.china)
                }
                Text("Automatic uses the China mirror only when this Mac's region or time zone is mainland China. Applies to the next download.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Files") {
                LabeledContent("System image") {
                    Text(coordinator.bootstrap.installedSystemImage()?.packagePath ?? "none").textSelection(.enabled)
                }
                HStack {
                    Button("Show Logs") { NSWorkspace.shared.open(coordinator.paths.logs) }
                    Button("Show Data Folder") { NSWorkspace.shared.open(coordinator.paths.root) }
                }
                Text("Data folder: \(coordinator.paths.root.path)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        // A grouped Form has no intrinsic height (it is a scroll view), so the
        // hosting window would collapse to zero height without an explicit size.
        .frame(width: 500, height: 780)
        .onChange(of: settings) { _, new in
            new.save()
            if !new.launcherStubs {
                LauncherStubBuilder.sync([])
            } else if !coordinator.apps.isEmpty {
                LauncherStubBuilder.sync(coordinator.apps)
            }
        }
    }

    private func restart(cold: Bool) {
        saved = settings
        windows.closeAll()
        Task { await coordinator.restart(coldBoot: cold) }
    }
}

final class SettingsWindowController: NSWindowController {
    init(coordinator: RunnerCoordinator, windows: WindowManager) {
        let host = NSHostingController(rootView: SettingsView(coordinator: coordinator, windows: windows))
        let window = NSWindow(contentViewController: host)
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }
    required init?(coder: NSCoder) { fatalError() }
}
