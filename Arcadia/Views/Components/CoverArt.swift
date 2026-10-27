import SwiftUI

/// A game's box art, or a generated cover in the system's colors while none is available.
struct CoverArt: View {
    let game: Game
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                // The whole cover over a blurred copy of itself, so any box shape fits the card.
                Color.clear
                    .overlay {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .blur(radius: 24)
                            .opacity(0.7)
                    }
                    .overlay {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .shadow(color: .black.opacity(0.4), radius: 10)
                    }
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .clipped()
        .task(id: game.id) {
            let loaded = await Artwork.shared.image(for: game)
            withAnimation(.easeOut(duration: 0.25)) { image = loaded }
        }
    }

    private var placeholder: some View {
        ZStack {
            game.system.gradient
            Image(systemName: game.system.symbol)
                .font(.system(size: 90, weight: .bold))
                .foregroundStyle(.white.opacity(0.08))
                .rotationEffect(.degrees(-12))
                .offset(x: 30, y: -30)
            VStack(alignment: .leading, spacing: 6) {
                Text(game.system.shortName.uppercased())
                    .font(.caption2.weight(.heavy))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text(game.title)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(4)
                    .minimumScaleFactor(0.7)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}
