import SwiftUI

/// A launch log to show in a sheet.
struct LaunchLog: Identifiable {
    let url: URL
    var id: URL { url }
}

/// The output an emulator printed during one launch.
struct LogView: View {
    let log: URL
    @Environment(\.dismiss) private var dismiss
    @State private var text: String?
    @State private var truncated = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 720, height: 520)
        .task {
            let url = log
            let tail = await Task.detached { LaunchLogs.tail(of: url) }.value
            text = tail.text
            truncated = tail.truncated
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Theme.accent.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Launch Log").font(.title2.weight(.bold))
                Text(verbatim: log.lastPathComponent)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        if let text {
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 8) {
                    if truncated {
                        Text("Only the end of this log is shown.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(verbatim: text)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize()
                }
                .padding(16)
            }
            // Short logs sit at the top; long ones open at the end, where the error usually is.
            .defaultScrollAnchor(.topLeading, for: .alignment)
            .defaultScrollAnchor(.bottomLeading, for: .initialOffset)
            .background(Color.black.opacity(0.25))
        } else {
            ProgressView()
        }
    }

    private var footer: some View {
        HStack {
            Text("Emulators write their messages here while a game runs.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Copy") {
                NSPasteboard.general.clearContents()
                let whole = (try? String(contentsOf: log, encoding: .utf8)) ?? text ?? ""
                NSPasteboard.general.setString(whole, forType: .string)
            }
            .disabled(text?.isEmpty ?? true)
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([log]) }
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }
}

/// Settings entry that opens the folder of launch logs.
struct LogsSettingsSection: View {
    var body: some View {
        Section("Logs") {
            Text("Arcadia keeps what the emulator printed during the last \(LaunchLogs.keep) game launches. It helps find out why a game didn't start.")
                .foregroundStyle(.secondary)
            Button("Open Logs Folder") {
                try? FileManager.default.createDirectory(at: LaunchLogs.folder, withIntermediateDirectories: true)
                NSWorkspace.shared.open(LaunchLogs.folder)
            }
        }
    }
}
