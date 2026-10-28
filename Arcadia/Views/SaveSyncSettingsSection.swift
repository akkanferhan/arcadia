import SwiftUI

/// Settings section for keeping saves in iCloud Drive.
struct SaveSyncSettingsSection: View {
    @Environment(AppModel.self) private var model
    private let sync = SaveSync.shared

    var body: some View {
        let playing = model.launcher.running != nil || model.launcher.preparing != nil
        Section {
            Toggle("Sync saves with iCloud Drive", isOn: Binding(
                get: { sync.isEnabled },
                set: { enabled in Task { await sync.setEnabled(enabled) } }
            ))
            // Turning sync off always works; it copies whatever iCloud Drive still has back to this Mac.
            .disabled(sync.isWorking || playing || (!sync.isAvailable && !sync.isEnabled))
            if sync.isWorking {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(sync.isEnabled ? "Copying saves back to this Mac…" : "Moving saves to iCloud Drive…")
                        .foregroundStyle(.secondary)
                }
            }
            if let error = sync.lastError {
                Text(error).foregroundStyle(.red)
            }
            if sync.lastConflicts > 0 {
                HStack {
                    Text("Some saves were different on this Mac and in iCloud Drive. Arcadia kept the newer ones and backed up the others.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Show Backups") { NSWorkspace.shared.open(sync.backupRoot) }
                }
            }
        } header: {
            Text("iCloud Drive")
        } footer: {
            Group {
                if !sync.isAvailable {
                    Text("iCloud Drive isn't available. Sign in to iCloud and turn on iCloud Drive in System Settings to sync your saves.")
                } else if playing {
                    Text("Quit the game to change this.")
                } else {
                    Text("Saves, save states and memory cards are kept in iCloud Drive in Arcadia › Saves, so you can continue on any Mac signed in to the same account.")
                }
            }
            .foregroundStyle(.secondary)
        }
        .onAppear { sync.refreshAvailability() }
    }
}
