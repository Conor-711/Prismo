import SwiftUI

struct BSmartCollapsingPager<Selection: Hashable, Header: View, Tabs: View, Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding private var selection: Selection
    @StateObject private var scrollState: BSmartCollapsingScrollState<Selection>
    @State private var headerHeight: CGFloat = 0
    @State private var tabHeight: CGFloat = 0
    @State private var headerDragOrigin: CGFloat?
    private let sections: [Selection]
    private let collapseHeader: Bool
    private let pageIdentifier: (Selection) -> String
    private let header: (CGSize) -> Header
    private let tabs: () -> Tabs
    private let content: (Selection) -> Content
    private let refresh: () async -> Void

    init(selection: Binding<Selection>, sections: [Selection], collapseHeader: Bool = false,
         pageIdentifier: @escaping (Selection) -> String,
         @ViewBuilder header: @escaping (CGSize) -> Header,
         @ViewBuilder tabs: @escaping () -> Tabs,
         @ViewBuilder content: @escaping (Selection) -> Content,
         refresh: @escaping () async -> Void) {
        _selection = selection
        _scrollState = StateObject(wrappedValue: BSmartCollapsingScrollState(selection: selection.wrappedValue))
        self.sections = sections
        self.collapseHeader = collapseHeader
        self.pageIdentifier = pageIdentifier
        self.header = header
        self.tabs = tabs
        self.content = content
        self.refresh = refresh
    }

    var body: some View {
        GeometryReader { viewport in
            ZStack(alignment: .top) {
                TabView(selection: $selection) {
                    ForEach(sections, id: \.self) { section in
                        ScrollView {
                            VStack(spacing: 0) {
                                Color.clear.frame(height: headerHeight + tabHeight)
                                content(section)
                                    .padding(BSmartSpacing.large)
                                    .padding(.bottom, 88)
                                    .frame(maxWidth: .infinity,
                                           minHeight: max(0, viewport.size.height - tabHeight),
                                           alignment: .topLeading)
                            }
                            .background(BSmartCollapsingScrollProbe(section: section, state: scrollState))
                        }
                        .refreshable { await refresh() }
                        .scrollIndicators(.hidden)
                        .scrollDismissesKeyboard(.interactively)
                        .accessibilityIdentifier(pageIdentifier(section))
                        .tag(section)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // A single header preserves chart state while each list keeps its own scroll position.
                VStack(spacing: 0) {
                    header(viewport.size)
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            guard abs(height - headerHeight) > 0.5 else { return }
                            headerHeight = height
                            scrollState.headerHeight = height
                        }
                        .simultaneousGesture(headerScrollGesture)
                    tabs()
                        .background(BSmartColor.ink)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tabHeight = $0 }
                        // Cancel a tab press when its moving header is dragged vertically.
                        .highPriorityGesture(headerScrollGesture)
                }
                .background(BSmartColor.ink)
                .offset(y: -scrollState.collapsedHeight)
            }
            .clipped()
            .onChange(of: selection) { _, section in scrollState.select(section) }
            .onChange(of: collapseHeader) { _, collapse in
                if collapse { scrollState.scrollHeader(to: max(headerHeight, scrollState.currentOffset)) }
            }
        }
    }

    private var headerScrollGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { value in
                guard headerDragOrigin != nil || abs(value.translation.height) > abs(value.translation.width) * 1.3 else { return }
                if headerDragOrigin == nil { headerDragOrigin = scrollState.currentOffset }
                scrollState.scrollHeader(to: (headerDragOrigin ?? 0) - value.translation.height)
            }
            .onEnded { value in
                guard let origin = headerDragOrigin else { return }
                headerDragOrigin = nil
                if origin < 1 && value.translation.height > 90 {
                    Task { await refresh() }
                } else {
                    scrollState.scrollHeader(to: origin - value.predictedEndTranslation.height, animated: !reduceMotion)
                }
            }
    }
}
