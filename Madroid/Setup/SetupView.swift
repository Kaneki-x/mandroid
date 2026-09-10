import MadroidKit
import SwiftUI

/// First-run download UI and boot progress.
struct SetupView: View {
    @Bindable var coordinator: RunnerCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "iphone.gen3.badge.play")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading) {
                    Text("Madroid").font(.title2.bold())
                    Text(subtitle).foregroundStyle(.secondary)
                }
            }
            content
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 480, height: 360)
    }

    private var subtitle: String {
        switch coordinator.state {
        case .needsSetup: return "A one-time download is needed."
        case .settingUp: return "Downloading components…"
        case .booting: return "Starting the Android emulator…"
        case .failed: return "Something went wrong."
        default: return "Checking installation…"
        }
    }

    @ViewBuilder private var content: some View {
        switch coordinator.state {
        case .needsSetup(let plan):
            planView(plan)
        case .settingUp(let phase):
            phaseView(phase)
        case .booting(let stage):
            HStack { ProgressView(); Text(stage) }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 12) {
                Text(message).font(.callout).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Try Again") { coordinator.retry() }.keyboardShortcut(.defaultAction)
            }
        default:
            HStack { ProgressView(); Text("Checking…") }
        }
    }

    private func planView(_ plan: BootstrapPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The following components will be downloaded from Google into your Application Support folder:")
                .fixedSize(horizontal: false, vertical: true)
            ForEach(plan.components) { c in
                HStack {
                    Text(c.displayName)
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: c.sizeBytes, countStyle: .file))
                        .foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Divider()
            HStack {
                Text("Total").bold()
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: plan.totalBytes, countStyle: .file)).bold().monospacedDigit()
            }
            Text("By continuing you accept the Android SDK License Agreement and the terms of the Google Play system image. Nothing outside this app's folder is modified.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Download and Install") { coordinator.runSetup(plan) }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    @ViewBuilder private func phaseView(_ phase: BootstrapPhase) -> some View {
        switch phase {
        case .fetchingManifests:
            HStack { ProgressView(); Text("Contacting dl.google.com…") }
        case .downloading(let name, let p):
            VStack(alignment: .leading, spacing: 8) {
                Text("Downloading \(name)")
                ProgressView(value: p.fraction ?? 0)
                HStack {
                    Text(ByteCountFormatter.string(fromByteCount: p.received, countStyle: .file))
                    if let total = p.total { Text("of \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))") }
                }
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Text("Downloads resume if the app is quit and reopened.").font(.caption2).foregroundStyle(.tertiary)
            }
        case .extracting(let name):
            HStack { ProgressView(); Text("Unpacking \(name)…") }
        case .finished:
            HStack { ProgressView(); Text("Starting…") }
        }
    }
}
