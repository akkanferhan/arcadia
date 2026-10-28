import SwiftUI

/// "Save Disk Space": lists disc images that can be compressed losslessly and compresses them.
struct SaveSpaceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let compressor = model.compressor
        let games = listedGames

        VStack(spacing: 0) {
            header
            Divider()
            Group {
                if games.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing to compress", systemImage: "checkmark.seal")
                    } description: {
                        Text(supportText)
                    }
                } else {
                    List {
                        ForEach(GameSystem.all) { system in
                            let rows = games.filter { $0.systemID == system.id }
                            if !rows.isEmpty {
                                Section {
                                    ForEach(rows) { game in
                                        SaveSpaceRow(game: game)
                                    }
                                } header: {
                                    HStack(spacing: 8) {
                                        SystemBadge(system: system, size: 18)
                                        Text(system.name)
                                    }
                                }
                            }
                        }
                        if compressor.focus == nil {
                            Section {
                                Text(supportText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer(games)
        }
        .frame(width: 640, height: 560)
        .onAppear { compressor.estimate(games) }
        .onChange(of: model.library.games) { compressor.estimate(listedGames) }
        .onDisappear {
            compressor.focus = nil
            compressor.clearFinished()
        }
    }

    /// The focused game alone, or every compressible game plus the ones handled this session.
    private var listedGames: [Game] {
        let compressor = model.compressor
        if let focus = compressor.focus { return [focus] }
        var seen = Set<String>()
        return (compressor.jobs + model.library.games.filter { CompressionPlan.plan(for: $0) != nil })
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private var supportText: String {
        String(localized: "Arcadia shrinks PSP and PS2 ISO files to CSO and GameCube ISO files to GCZ. CD images (BIN/CUE, GDI) and Wii discs need CHD or RVZ, whose official tools have no Mac version, so they are left as they are.")
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "internaldrive")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Theme.accent.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Save Disk Space").font(.title2.weight(.bold))
                Text("Compressing is lossless: games play exactly as before, from smaller files.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    private func footer(_ games: [Game]) -> some View {
        let compressor = model.compressor
        let waiting = games.filter { game in
            let stage = compressor.stage(game)
            return stage == nil || { if case .failed = stage { return true }; return false }()
        }
        let worthIt = waiting.filter { compressor.estimates[$0.id]?.worthIt == true }
        let savings = worthIt.compactMap { compressor.estimates[$0.id]?.savings }.reduce(0, +)

        return HStack {
            if compressor.savedSoFar > 0 {
                Label("Saved \(compressor.savedSoFar.formatted(.byteCount(style: .file)))", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            } else {
                Text("Originals go to the Trash only after the compressed copy is checked.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if compressor.focus != nil {
                Button("Show All Games") { compressor.focus = nil }
            }
            if compressor.isWorking {
                Button("Stop") { compressor.cancelAll() }
            }
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
            if compressor.focus == nil, !worthIt.isEmpty {
                Button("Compress All (Saves About \(savings.formatted(.byteCount(style: .file))))") {
                    compressor.compress(worthIt, library: model.library, launcher: model.launcher)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.large)
        .padding(16)
    }
}

private struct SaveSpaceRow: View {
    @Environment(AppModel.self) private var model
    let game: Game

    var body: some View {
        let compressor = model.compressor
        let estimate = compressor.estimates[game.id]
        let plan = CompressionPlan.plan(for: game)

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(game.title).lineLimit(1)
                HStack(spacing: 4) {
                    if let plan {
                        Text(verbatim: "\(game.url.pathExtension.uppercased()) → \(plan.format.name)")
                    }
                    if let size = estimate?.size, size > 0 {
                        Text(verbatim: "·")
                        Text(size.formatted(.byteCount(style: .file)))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            status(estimate: estimate)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func status(estimate: CompressionEstimate?) -> some View {
        let compressor = model.compressor
        switch compressor.stage(game) {
        case .queued?:
            Text("Waiting").foregroundStyle(.secondary)
            cancelButton
        case .compressing(let value)?:
            progress(value, label: "Compressing…")
            cancelButton
        case .verifying(let value)?:
            progress(value, label: "Checking…")
            cancelButton
        case .finished(let saved, let kept)?:
            if kept {
                Label("Compressed. The original could not be moved to the Trash.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .frame(maxWidth: 260, alignment: .trailing)
            } else {
                Label("Saved \(saved.formatted(.byteCount(style: .file)))", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        case .failed(let message)?:
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
                .lineLimit(2)
                .frame(maxWidth: 260, alignment: .trailing)
                .help(message)
            compressButton
        case nil:
            if let savings = estimate?.savings {
                if estimate?.worthIt == true {
                    Text("Saves about \(savings.formatted(.byteCount(style: .file)))").monospacedDigit()
                } else {
                    Text("Little to gain").foregroundStyle(.secondary)
                }
            } else {
                Text("Estimating…").foregroundStyle(.secondary)
            }
            compressButton
        }
    }

    private func progress(_ value: Double, label: LocalizedStringKey) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            ProgressView(value: value).frame(width: 140)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var cancelButton: some View {
        Button {
            model.compressor.cancel(game)
        } label: {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Cancel")
    }

    private var compressButton: some View {
        Button("Compress") {
            model.compressor.compress([game], library: model.library, launcher: model.launcher)
        }
        .disabled(CompressionPlan.plan(for: game) == nil)
    }
}
