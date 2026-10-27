import SwiftUI

enum Theme {
    static let accent = Color(hex: 0x7C5CFF)
    static let background = LinearGradient(
        colors: [Color(hex: 0x111218), Color(hex: 0x0A0A0F)],
        startPoint: .top, endPoint: .bottom)
    static let card = Color.white.opacity(0.05)
    static let stroke = Color.white.opacity(0.08)
    static let coverRatio: CGFloat = 3 / 4
}

extension TimeInterval {
    /// "2 h 15 min", "12 min" or "Under a minute".
    var playTimeText: String {
        guard self >= 60 else { return "Under a minute" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = self >= 3600 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .short
        return formatter.string(from: self) ?? ""
    }
}

/// Section title used on the home and grid pages.
struct SectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title2.weight(.bold))
            if let subtitle {
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Rounded square with a system's colors and symbol.
struct SystemBadge: View {
    let system: GameSystem
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(system.gradient)
            .overlay {
                Image(systemName: system.symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .shadow(color: system.colors[0].opacity(0.4), radius: size * 0.12, y: 1)
    }
}

/// Small capsule label such as "Experimental".
struct Tag: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }
}

/// Lifts a view slightly while the pointer is over it.
struct HoverLift: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? 1.035 : 1)
            .shadow(color: .black.opacity(hovering ? 0.5 : 0.25), radius: hovering ? 18 : 8, y: hovering ? 10 : 4)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverLift() -> some View { modifier(HoverLift()) }
}
