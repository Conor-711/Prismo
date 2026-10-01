import Foundation

extension SmartAccountProfile {
    var nativeProfileID: UUID? {
        guard platform.lowercased() == "bsmart", id.lowercased().hasPrefix("bsmart:") else { return nil }
        return UUID(uuidString: String(id.dropFirst("bsmart:".count)))
    }

    var nativePublicProfile: FeedPublicProfile? {
        guard let nativeProfileID else { return nil }
        return .init(id: nativeProfileID, nickname: name, avatarURL: avatarURL,
                     handle: handle.hasPrefix("@") ? String(handle.dropFirst()) : handle,
                     bio: description)
    }
}

extension FeedPublicProfile {
    func smartAccount(matching known: SmartAccountProfile? = nil) -> SmartAccountProfile {
        let investorID = "bsmart:" + id.uuidString.lowercased()
        let metadata = known.flatMap { $0.nativeProfileID == id ? $0 : nil }
        return SmartAccountProfile(
            id: investorID, name: nickname, handle: handle.map { "@" + $0 } ?? nickname,
            platform: "bsmart", score: metadata?.score ?? 0, scoreChange: metadata?.scoreChange ?? 0,
            specialty: metadata?.specialty ?? "On-platform trader", horizon: metadata?.horizon ?? "Verified trades",
            recentTicker: metadata?.recentTicker, rank: metadata?.rank, platformRank: metadata?.platformRank,
            platformPercentile: metadata?.platformPercentile, confidence: metadata?.confidence ?? "observing",
            effectiveSamples: metadata?.effectiveSamples, settledCalls: metadata?.settledCalls,
            activeDays: metadata?.activeDays, coveredTickers: metadata?.coveredTickers,
            topTickers: metadata?.topTickers, style: metadata?.style,
            marketSelectionScore: metadata?.marketSelectionScore, industrySelectionScore: metadata?.industrySelectionScore,
            rationale: metadata?.rationale, avatarURL: avatarURL, profileURL: metadata?.profileURL,
            followersCount: metadata?.followersCount, postsCount: metadata?.postsCount, verified: metadata?.verified,
            description: bio, representativeWork: metadata?.representativeWork,
            followBacktest: metadata?.followBacktest, nativePerformance: metadata?.nativePerformance)
    }
}
