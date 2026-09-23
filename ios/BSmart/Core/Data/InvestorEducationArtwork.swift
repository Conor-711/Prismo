import SwiftUI

@MainActor
final class InvestorEducationArtwork {
    let tiles: [Int: Image]

    init(snapshot: InvestorEducationSnapshot) {
        guard let url = Bundle.main.url(forResource: "InvestorEducationAtlas", withExtension: "jpg"),
              let image = UIImage(contentsOfFile: url.path)?.cgImage else { tiles = [:]; return }
        tiles = Dictionary(uniqueKeysWithValues: snapshot.authors.compactMap { author in
            let rect = CGRect(x: author.tile % snapshot.columns * snapshot.tile,
                              y: author.tile / snapshot.columns * snapshot.tile,
                              width: snapshot.tile, height: snapshot.tile)
            return image.cropping(to: rect).map { (author.tile, Image(decorative: $0, scale: 1)) }
        })
    }
}
