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


enum InvestorPortraitSource: Hashable {
    case bundled(String)
    case remote(URL)
    case placeholder

    init(imageURL: URL?, bundledAssetName: String?) {
        if let bundledAssetName, UIImage(named: bundledAssetName) != nil {
            self = .bundled(bundledAssetName)
        } else if let asset = AuthorAvatarAsset.name(for: imageURL), UIImage(named: asset) != nil {
            self = .bundled(asset)
        } else if let imageURL {
            self = .remote(imageURL)
        } else {
            self = .placeholder
        }
    }
}

struct InvestorPortraitHeader: View {
    let name: String
    let role: String
    let imageURL: URL?
    var bundledAssetName: String? = nil
    var isOrganization = false
    var portraitIdentifier = "investor.profile.portrait"
    var nameIdentifier: String? = nil
    let width: CGFloat
    var onCollapseChanged: (Bool) -> Void
    @State private var scrollOffset: CGFloat = 0
    @Environment(\.scenePhase) private var scenePhase
    @State private var loadedImage: AvatarImage?
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 34.0

    private var portraitSource: InvestorPortraitSource {
        InvestorPortraitSource(imageURL: imageURL, bundledAssetName: bundledAssetName)
    }

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
                    Text(role.bSmartLocalized)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 4))
                    Text(name)
                        .font(.system(size: titleSize, weight: .bold))
                        .lineLimit(2).minimumScaleFactor(0.65)
                        .accessibilityIdentifier(nameIdentifier ?? "\(portraitIdentifier).name")
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
        .accessibilityIdentifier(portraitIdentifier)
        .task(id: RequestKey(source: portraitSource, active: scenePhase == .active)) {
            guard scenePhase == .active, !isOrganization,
                  case let .remote(url) = portraitSource else { return }
            let image = await AvatarImageStore.shared.image(for: url)
            guard !Task.isCancelled else { return }
            loadedImage = image
        }
    }

    @ViewBuilder private var portrait: some View {
        if isOrganization {
            ZStack {
                Color(white: 0.13)
                BSmartAvatar(url: imageURL, name: name, size: 136,
                             bundledAssetName: bundledAssetName, isOrganization: true,
                             cornerRadius: 14)
            }
        } else if case let .bundled(asset) = portraitSource {
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

    private struct RequestKey: Hashable { let source: InvestorPortraitSource; let active: Bool }
}

struct SmartAccountPortraitHeader: View {
    let account: SmartAccountProfile
    let width: CGFloat
    var onCollapseChanged: (Bool) -> Void

    var body: some View {
        InvestorPortraitHeader(name: account.name, role: "Smart Account",
                               imageURL: account.avatarURL ?? RedditAuthorAvatars.url(forDisplayName: account.name),
                               portraitIdentifier: "smart.account.portrait",
                               nameIdentifier: account.nativeProfileID == nil ? nil : "feed.profile.nickname",
                               width: width, onCollapseChanged: onCollapseChanged)
    }
}

struct InvestorDetailScaffold<Portrait: View, Sections: View, Dock: View>: View {
    let title: String
    @Binding var collapsed: Bool
    let portrait: (CGFloat) -> Portrait
    let sections: Sections
    let dock: Dock

    init(title: String, collapsed: Binding<Bool>,
         @ViewBuilder portrait: @escaping (CGFloat) -> Portrait,
         @ViewBuilder sections: () -> Sections,
         @ViewBuilder dock: () -> Dock) {
        self.title = title
        _collapsed = collapsed
        self.portrait = portrait
        self.sections = sections()
        self.dock = dock()
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    portrait(geometry.size.width)
                    sections
                        .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 28)
                        .frame(maxWidth: 680)
                }
            }
            .contentMargins(.top, 0, for: .scrollContent)
            .ignoresSafeArea(.container, edges: .top)
            .coordinateSpace(name: "account.profile.scroll")
        }
        .ignoresSafeArea(.container, edges: .top)
        .safeAreaInset(edge: .bottom, spacing: 0) { dock }
        .navigationTitle(collapsed ? title : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(collapsed ? .visible : .hidden, for: .navigationBar)
        .toolbarColorScheme(collapsed ? nil : .dark, for: .navigationBar)
        .bSmartDetailPage()
        .bSmartPage()
    }
}
