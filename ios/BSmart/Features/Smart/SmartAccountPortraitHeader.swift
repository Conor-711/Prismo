import SwiftUI

struct SmartAccountPortraitLayout {
    let baseHeight: CGFloat
    let offset: CGFloat

    init(width: CGFloat, offset: CGFloat, minimumHeight: CGFloat = 260) {
        self.init(height: min(340, max(minimumHeight, width * 0.78)), offset: offset)
    }

    init(height: CGFloat, offset: CGFloat) {
        baseHeight = height
        self.offset = offset.isFinite ? offset : 0
    }

    var pull: CGFloat { max(0, offset) }
    var imageHeight: CGFloat { baseHeight + pull }
    var titleOpacity: Double { Double(max(0, 1 - pull / 100)) }
    var isCollapsed: Bool { offset < -(baseHeight - 110) }
}


struct SmartAccountPortraitHeader: View {
    let account: SmartAccountProfile
    let width: CGFloat
    var onCollapseChanged: (Bool) -> Void
    @State private var scrollOffset: CGFloat = 0
    @Environment(\.scenePhase) private var scenePhase
    @State private var loadedImage: AvatarImage?
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 34.0

    private var imageURL: URL? { account.avatarURL ?? RedditAuthorAvatars.url(forDisplayName: account.name) }

    var body: some View {
        let layout = SmartAccountPortraitLayout(width: width, offset: scrollOffset)
        Group {
            ZStack(alignment: .bottomLeading) {
                portrait
                    .frame(width: width, height: layout.imageHeight)
                    .clipped()
                    .accessibilityHidden(true)
                // The scrim belongs to the photograph, not the adaptive page surface.
                LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .center, endPoint: .bottom)
                    .opacity(layout.titleOpacity)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Smart Account")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 4))
                    Text(account.name)
                        .font(.system(size: titleSize, weight: .bold))
                        .lineLimit(2).minimumScaleFactor(0.65)
                        .accessibilityIdentifier("smart.account.portrait.name")
                }
                .foregroundStyle(.white)
                .padding(20)
                .opacity(layout.titleOpacity)
                .accessibilityHidden(layout.titleOpacity < 0.1)
            }
            .frame(width: width, height: layout.imageHeight)
            .offset(y: -layout.pull)
        }
        .frame(height: layout.baseHeight, alignment: .top)
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.frame(in: .named("account.profile.scroll")).minY
        } action: { offset in
            scrollOffset = offset
            onCollapseChanged(SmartAccountPortraitLayout(width: width, offset: offset).isCollapsed)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("smart.account.portrait")
        .task(id: RequestKey(url: imageURL, active: scenePhase == .active)) {
            guard scenePhase == .active, let url = imageURL, AuthorAvatarAsset.name(for: url) == nil else { return }
            let image = await AvatarImageStore.shared.image(for: url)
            guard !Task.isCancelled else { return }
            loadedImage = image
        }
    }

    @ViewBuilder private var portrait: some View {
        if let asset = AuthorAvatarAsset.name(for: imageURL) {
            Image(asset).resizable().scaledToFill()
        } else if let loadedImage, loadedImage.sourceURL == imageURL {
            Image(uiImage: loadedImage.image).resizable().scaledToFill()
        } else {
            ZStack {
                Color(white: 0.18)
                Image(systemName: "person.crop.square.fill")
                    .font(.system(size: 130, weight: .light))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
    }

    private struct RequestKey: Hashable { let url: URL?; let active: Bool }
}
