import SwiftUI

/// Install / progress / installed control for one emulator.
struct EmulatorButton: View {
    @Environment(AppModel.self) private var model
    let emulator: Emulator

    var body: some View {
        let emulators = model.emulators
        switch emulators.state(emulator.id) {
        case .notInstalled:
            Button {
                emulators.install(emulator)
            } label: {
                Label("Install", systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)

        case let .working(stage, progress):
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(stage.title).font(.caption).foregroundStyle(.secondary)
                    if let progress {
                        ProgressView(value: progress).frame(width: 120)
                    } else {
                        ProgressView().progressViewStyle(.linear).frame(width: 120)
                    }
                }
                Button {
                    emulators.cancel(emulator.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Cancel")
            }

        case .installed(let installation):
            Menu {
                Button("Update to Latest", systemImage: "arrow.triangle.2.circlepath") {
                    emulators.install(emulator)
                }
                Button("Show in Finder", systemImage: "folder") {
                    if let url = emulators.payloadURL(emulator.id) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                Divider()
                Button("Uninstall", systemImage: "trash", role: .destructive) {
                    emulators.uninstall(emulator.id)
                }
            } label: {
                Label(installation.version, systemImage: "checkmark.circle.fill")
            }
            .menuStyle(.button)
            .fixedSize()
            .tint(.green)

        case .failed(let message):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(message)
                Button("Retry") { emulators.install(emulator) }
            }
        }
    }
}
