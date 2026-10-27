import SwiftUI

/// First-run sheet: pick a games folder and Arcadia creates the system folders.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var folder = Paths.defaultLibrary

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(colors: [Theme.accent, Color(hex: 0x1B1340)], startPoint: .topLeading, endPoint: .bottomTrailing)
                HStack(spacing: -14) {
                    ForEach(["ps5", "nes", "megadrive", "xbox", "gba"], id: \.self) { id in
                        SystemBadge(system: GameSystem.with(id: id)!, size: 64)
                            .rotationEffect(.degrees(Double(id.count % 3 - 1) * 8))
                    }
                }
            }
            .frame(height: 170)

            VStack(spacing: 22) {
                VStack(spacing: 8) {
                    Text("Welcome to Arcadia")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("All your games, from the Atari 2600 to the PlayStation 5, in one place.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Step(number: 1, text: "Choose where your games live. Arcadia creates a folder for each system.")
                    Step(number: 2, text: "Drop your own game dumps into the folders, or drag them onto Arcadia.")
                    Step(number: 3, text: "Double-click a game. Arcadia downloads the right emulator for you.")
                }

                HStack {
                    Image(systemName: "folder.fill").foregroundStyle(Theme.accent)
                    Text(folder.path(percentEncoded: false))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Change…") { choose() }
                }
                .padding(12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button {
                    model.library.folder = folder
                    model.library.createFolders()
                    model.showOnboarding = false
                } label: {
                    Text("Get Started").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .padding(30)
        }
        .frame(width: 500)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { folder = url }
    }
}

private struct Step: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.callout.weight(.bold))
                .frame(width: 26, height: 26)
                .background(Theme.accent.opacity(0.25), in: Circle())
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
