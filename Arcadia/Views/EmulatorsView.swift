import SwiftUI

/// Every emulator Arcadia manages, with install controls.
struct EmulatorsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let missing = model.library.stockedSystems
            .map(\.emulatorID)
            .filter { !model.emulators.isInstalled($0) && !model.emulators.state($0).isWorking }

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .bottom) {
                    SectionHeader(title: "Emulators",
                                  subtitle: "Downloaded from each project's official releases. Arcadia never ships games or BIOS files.")
                    if !missing.isEmpty {
                        Button {
                            model.installNeededEmulators()
                        } label: {
                            Label("Install What My Games Need", systemImage: "wand.and.stars")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        .controlSize(.large)
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 16)], spacing: 16) {
                    ForEach(Emulator.all) { emulator in
                        EmulatorCard(emulator: emulator)
                    }
                }
            }
            .padding(32)
            .padding(.bottom, 80)
        }
    }
}

private struct EmulatorCard: View {
    let emulator: Emulator

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(emulator.name).font(.title3.weight(.bold))
                        if emulator.experimental { Tag(text: "Experimental", color: .orange) }
                        if emulator.needsRosetta { Tag(text: "Rosetta") }
                    }
                    Link(destination: emulator.website) {
                        Text(verbatim: "\(emulator.website.host() ?? "") · \(emulator.license)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                EmulatorButton(emulator: emulator)
            }

            FlowLayout(spacing: 6) {
                ForEach(emulator.systems) { system in
                    HStack(spacing: 5) {
                        SystemBadge(system: system, size: 16)
                        Text(system.shortName).font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.06), in: Capsule())
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke))
    }
}

/// Lays out children left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
