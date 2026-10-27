import SwiftUI
import UniformTypeIdentifiers

/// One line saying whether a system's BIOS is in place and what happens if not.
struct BiosStatusLabel: View {
    @Environment(AppModel.self) private var model
    let system: GameSystem

    var body: some View {
        let status = Bios.status(of: system, bios: model.library.biosFolder)
        Label {
            switch status {
            case .ready: Text("BIOS found")
            case .builtIn: Text("Using a built-in BIOS. Add your console's BIOS for the best compatibility.")
            case .willDownload: Text("System software downloads from Sony the first time you play.")
            case .missing: Text("BIOS needed. Drop it on the Emulators page or into the bios folder.")
            case .notNeeded: Text("No BIOS needed")
            }
        } icon: {
            Image(systemName: status.symbol).foregroundStyle(status.color)
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.85))
    }
}

extension BiosStatus {
    var symbol: String {
        switch self {
        case .ready, .notNeeded: "checkmark.circle.fill"
        case .builtIn: "cpu"
        case .willDownload: "arrow.down.circle.fill"
        case .missing: "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .ready, .notNeeded: .green
        case .builtIn, .willDownload: .blue
        case .missing: .orange
        }
    }
}

/// BIOS overview on the Emulators page. Dropped BIOS files are sorted into the right folders.
struct BiosCard: View {
    @Environment(AppModel.self) private var model
    @State private var targeted = false
    @State private var unknown: [String] = []
    @State private var refresh = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("BIOS & System Software").font(.title3.weight(.bold))
                    Text("Drop BIOS files dumped from your consoles here. Arcadia puts each one where its emulator looks.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open BIOS Folder") {
                    model.library.createFolders()
                    NSWorkspace.shared.open(model.library.biosFolder)
                }
            }

            VStack(spacing: 0) {
                ForEach(BiosRule.all, id: \.systemID) { rule in
                    let system = GameSystem.with(id: rule.systemID)!
                    let status = Bios.status(of: system, bios: model.library.biosFolder)
                    HStack(spacing: 12) {
                        SystemBadge(system: system, size: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(system.name).font(.callout.weight(.semibold))
                            Text(rule.hint).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                        Image(systemName: status.symbol).foregroundStyle(status.color).font(.title3)
                    }
                    .padding(.vertical, 8)
                    if rule.systemID != BiosRule.all.last?.systemID { Divider() }
                }
            }
            .id(refresh)

            if !unknown.isEmpty {
                Label {
                    Text("Not recognised as a BIOS: \(unknown.joined(separator: ", "))")
                } icon: {
                    Image(systemName: "questionmark.circle")
                }
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
        .padding(18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(targeted ? Theme.accent : Theme.stroke,
                              style: StrokeStyle(lineWidth: targeted ? 2 : 1, dash: targeted ? [8, 6] : []))
        }
        .dropDestination(for: URL.self) { urls, _ in
            unknown = model.importBios(urls)
            refresh += 1
            return true
        } isTargeted: { targeted = $0 }
    }
}
