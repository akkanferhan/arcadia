import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var launcher = model.launcher

        Form {
            Section("Library") {
                LabeledContent("Games folder") {
                    HStack {
                        Text(model.library.folder.path(percentEncoded: false))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Change…") { chooseFolder() }
                    }
                }
                HStack {
                    Button("Show in Finder") { NSWorkspace.shared.open(model.library.folder) }
                    Button("Create System Folders") { model.library.createFolders() }
                    Button("Rescan") { Task { await model.library.scan() } }
                }
            }
            Section("Playing") {
                Toggle("Start games in full screen", isOn: $launcher.fullscreen)
            }
            Section("BIOS") {
                Text("Some systems need BIOS or firmware files dumped from your own console. Put them in the bios folder inside your games folder.")
                    .foregroundStyle(.secondary)
                Button("Open BIOS Folder") {
                    model.library.createFolders()
                    NSWorkspace.shared.open(model.library.biosFolder)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = model.library.folder
        if panel.runModal() == .OK, let url = panel.url {
            model.library.folder = url
        }
    }
}
