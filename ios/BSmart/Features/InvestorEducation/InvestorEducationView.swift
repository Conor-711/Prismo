import SwiftUI

struct InvestorEducationView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var snapshot: InvestorEducationSnapshot?
    @State private var artwork: InvestorEducationArtwork?
    @State private var loadFailed = false
    @State private var focused = false
    @State private var entered = false
    @State private var showsDirectory = false
    @State private var platformID = InvestorEducationSnapshot.defaultPlatformID

    private var discovery: TodayInvestorDiscovery {
        TodayInvestorDiscovery(accounts: model.smartAccounts.filter { account in
            let identity = TodayInvestorDiscovery.identity(account.id, platform: account.platform)
            return identity.hasPrefix("\(platformID):")
        })
    }

    var body: some View {
        ScrollView {
            if let snapshot, let artwork, let platform = snapshot.platforms.first(where: { $0.id == platformID }) {
                VStack(spacing: 56) {
                    VStack(spacing: 4) {
                        platformPicker(snapshot)
                        hero(platform, artwork: artwork)
                    }
                    InvestorEducationCase(example: snapshot.example).padding(.horizontal, 22)
                    selection(platform, artwork: artwork).padding(.horizontal, 22)
                    methodology(platform, snapshotDate: snapshot.snapshotDate).padding(.horizontal, 22)
                }.padding(.bottom, 30)
            } else if loadFailed {
                ContentUnavailableView("Unable to load".bSmartLocalized, systemImage: "exclamationmark.circle")
            } else { ProgressView().padding(80) }
        }
        .navigationTitle("Why follow these investors?".bSmartLocalized)
        .navigationBarTitleDisplayMode(.inline)
        .bSmartPage().bSmartDetailPage()
        .accessibilityIdentifier("education.page")
        .task {
            guard snapshot == nil else { return }
            do {
                let value = try await Task.detached(priority: .userInitiated) { try InvestorEducationSnapshot.load() }.value
                guard !Task.isCancelled else { return }
                artwork = InvestorEducationArtwork(snapshot: value)
                snapshot = value
                withAnimation(reduceMotion ? nil : .easeOut(duration: 1.0)) { entered = true }
            } catch { loadFailed = true }
        }
        .sheet(isPresented: $showsDirectory) {
            TodayInvestorDiscoveryDirectory(discovery: discovery, sector: nil)
        }
    }

    private func platformPicker(_ value: InvestorEducationSnapshot) -> some View {
        HStack(spacing: 8) {
            ForEach(value.displayPlatforms) { platform in
                Button {
                    focused = false
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { platformID = platform.id }
                } label: {
                    HStack(spacing: 7) {
                        SmartPlatformMark(platform: platform.name, size: 18)
                        Text(platform.name).font(.subheadline.bold())
                    }
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .foregroundStyle(platformID == platform.id ? BSmartColor.brand : BSmartColor.secondaryText)
                    .background(platformID == platform.id ? BSmartColor.brand.opacity(0.12) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("education.platform.\(platform.id)")
                .accessibilityAddTraits(platformID == platform.id ? .isSelected : [])
            }
        }.padding(.horizontal, 22).padding(.top, 14)
    }

    private func hero(_ value: InvestorEducationSnapshot.Platform, artwork: InvestorEducationArtwork) -> some View {
        ZStack {
            InvestorEducationPool(platform: value, tiles: artwork.tiles).id(value.id)
                .scaleEffect(entered ? 1 : 1.12).opacity(0.8).allowsHitTesting(false)
            VStack(spacing: 20) {
                Text("Investing. Who should you follow?".bSmartLocalized)
                    .font(.system(size: 29, weight: .bold)).multilineTextAlignment(.center)
                    .accessibilityIdentifier("education.headline")
                Text(value.headlineCount).font(.system(size: 76, weight: .bold)).monospacedDigit().minimumScaleFactor(0.7)
                    .accessibilityIdentifier("education.population")
                Text("%@ stock investors, researched for you.".bSmartLocalized(value.name))
                    .font(.system(size: 20, weight: .semibold)).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24).padding(.vertical, 22)
            .background(BSmartColor.ink).padding(.horizontal, 25)
        }
        .frame(height: 550).clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("education.hero")
    }

    private func selection(_ value: InvestorEducationSnapshot.Platform, artwork: InvestorEducationArtwork) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("We compare the records.\nYou choose who to follow.".bSmartLocalized)
                .font(.system(size: 29, weight: .bold)).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline) {
                Text("Top 25%").font(.system(size: 38, weight: .bold)).foregroundStyle(BSmartColor.brand)
                Spacer()
            }
            InvestorEducationPool(platform: value, tiles: artwork.tiles, progress: focused ? 1 : 0).id(value.id)
                .frame(height: 320).clipped().accessibilityIdentifier("education.pool")
            Button {
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.85)) { focused.toggle() }
            } label: {
                Label((focused ? "Show the full pool" : "See who stands out").bSmartLocalized,
                      systemImage: focused ? "arrow.uturn.backward" : "person.crop.circle.badge.checkmark")
                    .font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 50)
                    .background(BSmartColor.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }.buttonStyle(.plain).foregroundStyle(BSmartColor.brand).accessibilityIdentifier("education.filter")
            Text("Follow them. Find their next stock idea in Tracking.".bSmartLocalized)
                .font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
            ForEach(Array(discovery.candidates(sector: nil).sorted { lhs, rhs in
                let left = value.authors.contains { $0.id == lhs.account.id }
                let right = value.authors.contains { $0.id == rhs.account.id }
                if left != right { return left }
                return lhs.account.resolvedPlatformRank < rhs.account.resolvedPlatformRank
            }.prefix(3))) { investor in
                HStack(spacing: 12) {
                    if let author = value.authors.first(where: { $0.id == investor.account.id }), let image = artwork.tiles[author.tile] {
                        image.resizable().scaledToFill().frame(width: 45, height: 45).clipShape(Circle())
                    } else {
                        BSmartAvatar(url: investor.account.avatarURL, name: investor.account.name, size: 45)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(investor.account.name).font(.subheadline.bold()).lineLimit(2)
                        Text(investor.account.platform).font(.caption).foregroundStyle(BSmartColor.secondaryText)
                    }
                    Spacer()
                    Button { model.toggleSmartAccountFollow(investor.account.id) } label: {
                        Image(systemName: model.isFollowingSmartAccount(investor.account.id) ? "checkmark" : "plus")
                            .font(.body.bold()).frame(width: 44, height: 44)
                            .background(BSmartColor.brand.opacity(0.12), in: Circle())
                    }.buttonStyle(.plain).foregroundStyle(BSmartColor.brand)
                        .accessibilityLabel((model.isFollowingSmartAccount(investor.account.id) ? "Following" : "Follow").bSmartLocalized)
                }.padding(.vertical, 4).accessibilityIdentifier("education.investor.\(investor.account.id)")
            }
            Button { showsDirectory = true } label: {
                HStack { Text("Discover investors".bSmartLocalized); Spacer(); Image(systemName: "arrow.right") }
                    .font(.headline).padding(18).foregroundStyle(BSmartColor.onAccent)
                    .background(BSmartColor.brand, in: RoundedRectangle(cornerRadius: 6))
            }.buttonStyle(.plain).accessibilityIdentifier("education.discover")
        }
    }

    private func methodology(_ value: InvestorEducationSnapshot.Platform, snapshotDate: String) -> some View {
        DisclosureGroup("About these records".bSmartLocalized) {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(value.name) · \(value.totalObserved) → \(value.rankedCount) → \(value.selectedCount)")
                Text("Observed authors, qualified rankings, then the platform's Top 25%. Too little history does not mean a poor investor.".bSmartLocalized)
                Text("Historical snapshot: %@".bSmartLocalized(snapshotDate))
                Text("%d real investor portraits".bSmartLocalized(value.authors.count))
                Text("Past performance does not guarantee future results.".bSmartLocalized)
                Text("A selected positive historical example, not typical or guaranteed returns. Stock performance is not the author's account return.".bSmartLocalized)
            }.font(.caption).foregroundStyle(BSmartColor.secondaryText).padding(.top, 12)
        }.font(.subheadline).tint(BSmartColor.secondaryText)
    }
}
