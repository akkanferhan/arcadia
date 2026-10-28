import SwiftUI

/// "Find Games on This Mac": pick places, search, review, add.
struct FindGamesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var locations: [Location] = GameFinder.suggestedLocations.map { Location(url: $0, enabled: true) }
    @State private var added: Int?

    struct Location: Identifiable {
        let url: URL
        var enabled: Bool
        var id: String { url.path }
    }

    var body: some View {
        let finder = model.finder

        VStack(spacing: 0) {
            header
            Divider()
            Group {
                switch finder.phase {
                case .idle: start
                case .scanning: scanning
                case .done, .adding: results
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 640, height: 560)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Theme.accent.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Find Games on This Mac").font(.title2.weight(.bold))
                Text("Arcadia looks inside your folders and drives and recognises each game's console.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    // MARK: Start

    private var start: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Where should Arcadia look?").font(.headline)
            VStack(spacing: 0) {
                ForEach($locations) { $location in
                    Toggle(isOn: $location.enabled) {
                        HStack(spacing: 10) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: location.url.path))
                                .resizable()
                                .frame(width: 24, height: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(FileManager.default.displayName(atPath: location.url.path))
                                Text(location.url.path(percentEncoded: false))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                    .padding(.vertical, 8)
                    Divider()
                }
                Button {
                    addFolder()
                } label: {
                    Label("Add a Folder…", systemImage: "plus")
                }
                .buttonStyle(.link)
                .padding(.top, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            if let added {
                Label("Added \(added) games to your library.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            Label("macOS may ask whether Arcadia can open folders such as Desktop, Documents or Downloads. Allow it so games there can be found.",
                  systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(20)
    }

    // MARK: Scanning

    private var scanning: some View {
        let finder = model.finder
        return VStack(spacing: 16) {
            Spacer()
            ProgressView().controlSize(.large)
            Text("Searching…").font(.title3.weight(.semibold))
            Text("Games found: \(finder.found.count) · Files checked: \(finder.scannedFiles)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text(finder.currentFolder)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 480)
            Spacer()
        }
        .padding(20)
    }

    // MARK: Results

    private var results: some View {
        @Bindable var finder = model.finder
        let recognised = finder.found.indices.filter { finder.found[$0].systemID != nil && !finder.found[$0].needsReview }
        let review = finder.found.indices.filter { finder.found[$0].needsReview }

        return Group {
            if finder.found.isEmpty {
                ContentUnavailableView("No new games found", systemImage: "magnifyingglass",
                                       description: Text("Try another folder or drive."))
            } else {
                List {
                    ForEach(GameSystem.all) { system in
                        let rows = recognised.filter { finder.found[$0].systemID == system.id }
                        if !rows.isEmpty {
                            Section {
                                ForEach(rows, id: \.self) { index in
                                    FoundRow(item: $finder.found[index])
                                }
                            } header: {
                                HStack(spacing: 8) {
                                    SystemBadge(system: system, size: 18)
                                    Text(system.name)
                                    Text("\(rows.count)").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if !review.isEmpty {
                        Section {
                            ForEach(review, id: \.self) { index in
                                FoundRow(item: $finder.found[index], choosesSystem: true)
                            }
                        } header: {
                            Label("Check these", systemImage: "questionmark.circle")
                        } footer: {
                            Text("Arcadia could not be sure which console these belong to. Pick one to add them.")
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var footer: some View {
        let finder = model.finder
        let selected = finder.found.filter { $0.selected && $0.systemID != nil }.count

        return HStack {
            Text("Games stay where they are; Arcadia adds links to them in your library.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            switch finder.phase {
            case .idle:
                Button("Close") { dismiss() }
                Button("Search") {
                    added = nil
                    finder.start(in: locations.filter(\.enabled).map(\.url), library: model.library)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(!locations.contains(where: \.enabled))
                .keyboardShortcut(.defaultAction)
            case .scanning:
                Button("Stop") { finder.cancel() }
            case .done, .adding:
                Button("Search Again") { finder.reset() }
                Button("Add \(selected) Games") {
                    Task {
                        added = await finder.add(to: model.library)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(selected == 0 || finder.phase == .adding)
                .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.large)
        .padding(16)
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !locations.contains(where: { $0.url == url }) {
            locations.append(Location(url: url, enabled: true))
        }
    }
}

private struct FoundRow: View {
    @Binding var item: GameFinder.Found
    var choosesSystem = false

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $item.selected)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(item.systemID == nil)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).lineLimit(1)
                Text(item.url.deletingLastPathComponent().path(percentEncoded: false))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if choosesSystem {
                Picker("", selection: Binding(get: { item.systemID ?? "" }, set: { value in
                    item.systemID = value.isEmpty ? nil : value
                    item.selected = !value.isEmpty
                })) {
                    Text("Choose…").tag("")
                    ForEach(GameSystem.all) { system in
                        Text(system.name).tag(system.id)
                    }
                }
                .labelsHidden()
                .frame(width: 190)
            }
        }
    }
}
