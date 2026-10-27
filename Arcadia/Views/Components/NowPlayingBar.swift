import SwiftUI

/// Floating bar that shows the game being started or played.
struct NowPlayingBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let launcher = model.launcher
        if let game = launcher.running ?? launcher.preparing {
            HStack(spacing: 14) {
                CoverArt(game: game)
                    .frame(width: 40, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    (launcher.running == nil ? Text("Starting…") : Text("Now playing"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(game.title).font(.headline).lineLimit(1)
                    if launcher.running == nil, let status = launcher.preparingStatus {
                        Text(status).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(game.system.name).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 20)
                if launcher.running != nil {
                    Button(role: .destructive) {
                        launcher.stop()
                    } label: {
                        Label("Quit Game", systemImage: "stop.fill")
                    }
                    .controlSize(.large)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: 520)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.stroke))
            .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
