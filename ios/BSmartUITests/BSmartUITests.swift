import XCTest

final class BSmartUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testRootNavigationShowsFiveTabsInRequestedOrder() {
        let app = launch(scenario: "loaded")

        XCTAssertTrue(app.descendants(matching: .any)["app.tab.today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["app.tab.portfolio"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["app.tab.search"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["app.tab.feed"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["app.tab.friends"].exists)
        XCTAssertLessThan(
            app.descendants(matching: .any)["app.tab.today"].frame.minX,
            app.descendants(matching: .any)["app.tab.search"].frame.minX
        )
        XCTAssertLessThan(app.buttons["app.tab.search"].frame.minX, app.buttons["app.tab.feed"].frame.minX)
        XCTAssertLessThan(app.buttons["app.tab.feed"].frame.minX, app.buttons["app.tab.friends"].frame.minX)
        XCTAssertLessThan(app.buttons["app.tab.friends"].frame.minX, app.buttons["app.tab.portfolio"].frame.minX)
        app.buttons["app.tab.friends"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["friends.screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["friends.tab.Chats"].isSelected)
        XCTAssertFalse(app.segmentedControls.firstMatch.exists)
        let chatsPage = app.scrollViews["friends.page.Chats"]
        XCTAssertTrue(chatsPage.exists)
        chatsPage.swipeLeft()
        XCTAssertFalse(app.buttons["friends.tab.Follows"].exists)
        XCTAssertTrue(app.buttons["friends.tab.Activity"].isSelected)
        app.buttons["friends.tab.Chats"].tap()
        XCTAssertTrue(app.buttons["friends.tab.Chats"].isSelected)
    }

    func testLoadedPortfolioOpensTodayWithoutBlockingLoader() {
        let app = launch(scenario: "loaded")

        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["today.discovery"].exists)
        XCTAssertFalse(app.buttons["today.scope.holdings"].exists)
        XCTAssertTrue(app.staticTexts["discovery.heading"].exists)
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "published a")
        ).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Loading your portfolio"].exists)
    }

    func testTickerDetailDefaultsToLiveHyperliquidTrading() {
        let app = launch(scenario: "loaded")

        tab(.portfolio, in: app).tap()
        let nvda = app.descendants(matching: .any)["portfolio.entry.NVDA"]
        XCTAssertTrue(nvda.waitForExistence(timeout: 5))
        nvda.tap()

        XCTAssertTrue(app.descendants(matching: .any)["trading-account.summary"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.descendants(matching: .any)["trade.market-picker"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["hyperliquid.chart"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["TRADING ACCOUNT"].exists)
        XCTAssertFalse(app.staticTexts["Smart Money"].exists)
        keepScreenshot(app, named: "Hyperliquid trading ticker detail")
    }

    func testTodayRecentActivityUsesInformativeHeadlines() {
        let app = launch(scenario: "loaded", language: "zh-Hans")

        XCTAssertTrue(app.descendants(matching: .any)["today.screen"].waitForExistence(timeout: 5))
        let informativeHeadline = app.staticTexts["维持 NVDA 长期看多判断"]
        for _ in 0..<4 {
            if informativeHeadline.exists && informativeHeadline.isHittable { break }
            app.swipeUp()
        }

        XCTAssertTrue(informativeHeadline.exists)
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "发布了关于")
        ).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "发表了关于")
        ).firstMatch.exists)
    }

    func testTodayViewpointCollectionOpensAsDedicatedEditorialPage() {
        let app = launch(scenario: "loaded", language: "zh-Hans")

        XCTAssertTrue(app.descendants(matching: .any)["today.discovery"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["today.scope.holdings"].exists)
        XCTAssertFalse(app.buttons["today.scope.watchlist"].exists)
        XCTAssertTrue(app.staticTexts["discovery.heading"].exists)

        selectTodayMarket(app)

        let package = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "today.viewpoint-package.")
        ).firstMatch
        XCTAssertTrue(package.waitForExistence(timeout: 3))
        keepScreenshot(app, named: "Today editorial collections")
        package.tap()

        let back = app.buttons["today.viewpoint-package.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 4))
        let tradeDock = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "trade.dock.")
        ).firstMatch
        XCTAssertTrue(tradeDock.waitForExistence(timeout: 3))
        XCTAssertFalse(app.navigationBars["NVDA"].exists)
        XCTAssertTrue(app.staticTexts["热门标的"].exists)
        XCTAssertTrue(app.staticTexts["核心 Smart Account"].exists)
        let leadingAccount = app.descendants(matching: .any)["today.consensus-leading-account.0"]
        XCTAssertTrue(leadingAccount.exists)
        bringIntoReadingArea(leadingAccount, in: app)
        // The identity opens the profile; the trailing disclosure expands the opinion.
        leadingAccount.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "today.inline-account-opinion.")
        ).firstMatch.waitForExistence(timeout: 2))
        XCTAssertFalse(app.descendants(matching: .any)["app.tabbar"].exists)
        keepScreenshot(app, named: "Today editorial collection detail")

        XCTAssertTrue(back.isHittable)
        back.tap()
        XCTAssertTrue(app.descendants(matching: .any)["app.tabbar"].exists)
        XCTAssertTrue(package.waitForExistence(timeout: 4))
        XCTAssertTrue(package.isHittable)
        keepScreenshot(app, named: "Today editorial collection returned")
    }

    func testTodayViewpointCollectionCardStaysCompact() {
        let app = launch(scenario: "loaded", language: "zh-Hans")

        XCTAssertTrue(app.descendants(matching: .any)["today.discovery"].waitForExistence(timeout: 5))
        selectTodayMarket(app)
        let page = app.descendants(matching: .any)["today.viewpoint-preview"]
        alignTrendingPage(page, in: app)
        let cards = page.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "today.viewpoint-package."))
        XCTAssertEqual(cards.count, 2)
        let package = cards.element(boundBy: 0)
        let lower = cards.element(boundBy: 1)
        XCTAssertTrue(package.isHittable)
        XCTAssertTrue(lower.isHittable)
        XCTAssertEqual(package.frame.height, 232, accuracy: 1)
        XCTAssertEqual(lower.frame.height, package.frame.height, accuracy: 1)
        XCTAssertEqual(lower.frame.width, package.frame.width, accuracy: 1)
        XCTAssertEqual(lower.frame.minX, package.frame.minX, accuracy: 1)
        XCTAssertEqual(lower.frame.minY - package.frame.maxY, 12, accuracy: 1)

        let summary = package.staticTexts["today.consensus-card.summary"]
        XCTAssertEqual(package.staticTexts.matching(identifier: "today.consensus-card.summary").count, 1)
        XCTAssertTrue(package.frame.contains(summary.frame))
        XCTAssertTrue(package.descendants(matching: .any)["today.consensus-card.account.2"].exists)
        // Profile navigation owns the footer's accessibility identity, including its name and time.
        let footerElements = package.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "subject.account.")
        ).allElementsBoundByIndex.filter { $0.frame.minY >= summary.frame.maxY }
        XCTAssertFalse(footerElements.isEmpty, package.debugDescription)
        XCTAssertTrue(footerElements.allSatisfy { package.frame.contains($0.frame) })

        let labels = package.staticTexts.allElementsBoundByIndex.map(\.label)
        XCTAssertFalse(labels.contains("热门标的"))
        XCTAssertFalse(labels.contains("多方观点"))
        XCTAssertFalse(labels.contains { $0.contains("维持看多") })
        XCTAssertFalse(labels.contains { $0.contains("观望") })
        keepScreenshot(app, named: "Trending paired cards - first group")

        XCTAssertFalse(app.descendants(matching: .any)["today.viewpoint-page-progress"].exists)
        lower.tap()
        let back = app.buttons["today.viewpoint-package.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["today.tab.market"].isSelected)

        app.buttons["today.consensus.title"].tap()
        let libraryCards = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "today.consensus-library.")
        )
        XCTAssertTrue(libraryCards.firstMatch.waitForExistence(timeout: 3))
        let first = libraryCards.element(boundBy: 0)
        let second = libraryCards.element(boundBy: 1)
        XCTAssertTrue(second.exists)
        XCTAssertEqual(first.frame.height, 264, accuracy: 1)
        XCTAssertEqual(second.frame.height, first.frame.height, accuracy: 1)
        XCTAssertEqual(second.frame.width, first.frame.width, accuracy: 1)
        XCTAssertTrue(first.frame.contains(first.staticTexts["today.consensus-card.summary"].frame))
        keepScreenshot(app, named: "Trending tickers shared card layout")
    }

    private func selectTodayMarket(_ app: XCUIApplication) {
        selectTodayScene("market", in: app)
    }

    private func selectTodayScene(_ section: String, in app: XCUIApplication) {
        let tab = app.buttons["today.tab.\(section)"]
        for _ in 0..<8 {
            if tab.isHittable && tab.frame.minY < 100 { break }
            app.swipeUp()
        }
        XCTAssertTrue(tab.isHittable)
        tab.tap()
    }

    private func bringIntoReadingArea(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            let frame = element.frame
            if element.isHittable && frame.minY >= 115 && frame.maxY <= app.frame.height - 120 { return }
            let delta = frame.midY - app.frame.height * 0.45
            let distance = min(max(abs(delta) / app.frame.height, 0.12), 0.4)
            let start = delta > 0 ? 0.70 : 0.25
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: start))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset:
                    CGVector(dx: 0.95, dy: start + (delta > 0 ? -distance : distance))),
                       withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTAssertTrue(element.isHittable)
    }

    private func alignTrendingPage(_ page: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            if page.exists {
                let delta = page.frame.minY - 120
                if abs(delta) < 35 { return }
                let distance = min(abs(delta) / app.frame.height, 0.45)
                let startY = delta > 0 ? 0.72 : 0.22
                let endY = startY + (delta > 0 ? -distance : distance)
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: startY))
                    .press(forDuration: 0.05,
                           thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: endY)),
                           withVelocity: .slow, thenHoldForDuration: 0.2)
            } else {
                app.swipeUp()
            }
        }
        XCTAssertTrue(page.exists)
    }

    func testTodaySmartAlphaOpensDedicatedEvidencePage() {
        let app = launch(scenario: "loaded", language: "zh-Hans")

        XCTAssertTrue(app.descendants(matching: .any)["today.discovery"].waitForExistence(timeout: 5))
        selectTodayMarket(app)
        let alphaCard = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "today.smart-alpha.")
        ).firstMatch

        for _ in 0..<7 {
            if alphaCard.exists && alphaCard.isHittable { break }
            app.swipeUp()
        }

        XCTAssertTrue(alphaCard.waitForExistence(timeout: 3))
        bringIntoReadingArea(alphaCard, in: app)
        XCTAssertTrue(alphaCard.isHittable)
        XCTAssertGreaterThanOrEqual(alphaCard.frame.height, 270)
        XCTAssertLessThanOrEqual(alphaCard.frame.height, 274)
        let previewLabels = alphaCard.staticTexts.allElementsBoundByIndex.map(\.label)
        XCTAssertFalse(previewLabels.contains("阿尔法标的"))
        XCTAssertFalse(previewLabels.contains("发现类型"))
        XCTAssertFalse(previewLabels.contains("头部覆盖"))
        XCTAssertFalse(previewLabels.contains("更新于"))
        keepScreenshot(app, named: "Today Alpha Tickers module")
        alphaCard.tap()

        XCTAssertTrue(app.buttons["today.smart-alpha.back"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "trade.dock.")
        ).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["阿尔法标的"].exists)
        XCTAssertTrue(app.staticTexts["研究候选 · 不代表推荐"].exists)
        XCTAssertTrue(app.staticTexts["为什么被发现"].exists)
        XCTAssertTrue(app.staticTexts["原始证据"].exists)
        let alphaAccount = app.descendants(matching: .any)["today.smart-alpha-account.0"]
        if alphaAccount.exists {
            alphaAccount.tap()
            XCTAssertTrue(app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "today.inline-account-opinion.")
            ).firstMatch.waitForExistence(timeout: 2))
        }
        XCTAssertFalse(app.descendants(matching: .any)["app.tabbar"].exists)
        keepScreenshot(app, named: "Today Alpha Tickers detail")
        app.buttons["today.smart-alpha.back"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["app.tabbar"].exists)
    }

    func testTodayInvestorViewOpensViewDetailInsteadOfAccountProfile() {
        let app = launch(scenario: "loaded")
        selectTodayScene("investors", in: app)
        app.buttons["today.smart-updates.title"].tap()
        app.segmentedControls["smart-updates.source-filter"].buttons["Smart Account"].tap()
        let representativeView = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "smart-updates.evidence.account.")
        ).firstMatch
        XCTAssertTrue(representativeView.waitForExistence(timeout: 3))
        representativeView.tap()

        XCTAssertTrue(app.descendants(matching: .any)["smart.account.evidence.detail"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["smart.account.trust-preview"].exists)
    }

    func testTodaySmartUpdatesOpenAnInvestorCollection() {
        let app = launch(scenario: "loaded", language: "zh-Hans")
        selectTodayScene("investors", in: app)

        let viewAll = app.buttons["today.smart-updates.title"]
        for _ in 0..<20 {
            if viewAll.exists && viewAll.isHittable { break }
            app.swipeUp()
        }

        XCTAssertTrue(viewAll.exists)
        XCTAssertTrue(viewAll.isHittable)
        keepScreenshot(app, named: "Today before Smart updates")
        viewAll.tap()

        XCTAssertTrue(app.descendants(matching: .any)["smart-updates.collection"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.navigationBars["聪明动态"].exists)
        keepScreenshot(app, named: "Today Smart updates")
    }

    func testTodayDiscoveryOpensInvestorProfile() {
        let app = launch(scenario: "loaded", language: "zh-Hans")

        let profile = app.buttons["discovery.profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 8))
        keepScreenshot(app, named: "Today discovery pool")
        profile.tap()
        XCTAssertFalse(app.descendants(matching: .any)["app.tabbar"].exists)
        keepScreenshot(app, named: "Today discovered investor profile")
        let detailBack = app.buttons["detail.back"]
        XCTAssertTrue(detailBack.waitForExistence(timeout: 2))
        detailBack.tap()
        XCTAssertTrue(app.descendants(matching: .any)["app.tabbar"].exists)
    }

    func testWeightOnlyPortfolioUsesMonitoringSummaryInsteadOfZeroValue() {
        let app = launch(scenario: "weight-only")

        XCTAssertTrue(app.descendants(matching: .any)["today.discovery"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["discovery.heading"].exists)
        XCTAssertFalse(app.staticTexts["US$0"].exists)
        XCTAssertFalse(app.staticTexts["$0"].exists)
    }

    func testNoSignalStateRemainsInsideToday() {
        let app = launch(scenario: "no-signals")

        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No recent smart activity"].waitForExistence(timeout: 2))
    }

    func testInitialFailureOffersRetry() {
        let app = launch(scenario: "error")

        XCTAssertTrue(app.staticTexts["Unable to load bSmart"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Try again"].exists)
    }

    func testSlowInitialLoadUsesDedicatedLoadingState() {
        let app = launch(scenario: "loading")

        XCTAssertTrue(app.staticTexts["Loading your portfolio"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Today"].exists)
    }

    func testLeadActivityExpandsAuditableEvidenceInsideToday() {
        let app = launch(scenario: "loaded")

        let accountsFilter = app.buttons["today.filter.accounts"]
        XCTAssertTrue(accountsFilter.waitForExistence(timeout: 5))
        accountsFilter.tap()

        let lead = app.buttons["today.lead-activity"]
        XCTAssertTrue(lead.waitForExistence(timeout: 3))
        lead.tap()

        XCTAssertTrue(app.staticTexts["Original view evidence"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Open source"].exists)
    }

    func testTodayAuthorOpensTrustPreviewWithoutExpandingTheView() {
        let app = launch(scenario: "loaded")

        let accountsFilter = app.buttons["today.filter.accounts"]
        XCTAssertTrue(accountsFilter.waitForExistence(timeout: 5))
        accountsFilter.tap()

        let author = app.buttons["today.smart-account-preview"].firstMatch
        XCTAssertTrue(author.waitForExistence(timeout: 3))
        author.tap()

        XCTAssertTrue(app.descendants(matching: .any)["smart.account.trust-preview"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Recent summary"].exists)
        XCTAssertTrue(app.staticTexts["Investment strategy profile"].exists)
        XCTAssertTrue(app.staticTexts["Representative works"].exists)
        XCTAssertFalse(app.staticTexts["Original view evidence"].exists)

        let rank = app.buttons["smart.account.trust-preview.rank"]
        XCTAssertTrue(rank.exists)
        rank.tap()
        XCTAssertTrue(app.staticTexts["What this ranking means"].waitForExistence(timeout: 2))
        keepScreenshot(app, named: "Today Smart Account trust preview")
    }

    func testSmartAccountCanBeFollowedFromDetail() {
        let app = launch(scenario: "loaded")

        XCTAssertEqual(tab(.smart, in: app).label, "Smart")
        tab(.smart, in: app).tap()
        XCTAssertTrue(app.descendants(matching: .any)["smart.screen"].waitForExistence(timeout: 5))

        let account = app.descendants(matching: .any)["smart.account.row.first"]
        XCTAssertTrue(account.waitForExistence(timeout: 3))
        XCTAssertFalse(account.descendants(matching: .staticText).matching(
            NSPredicate(format: "label CONTAINS[c] %@", "N_eff")
        ).firstMatch.exists)
        let identity = account.descendants(matching: .any)["smart.account.row.identity"]
        XCTAssertTrue(identity.exists)
        XCTAssertFalse(identity.label.localizedCaseInsensitiveContains("followers"))
        keepScreenshot(app, named: "Smart Account visual preview")
        account.tap()

        let follow = app.buttons["smart.account.follow"]
        XCTAssertTrue(follow.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Investor profile"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Current ticker views"].exists)
        XCTAssertTrue(app.staticTexts["Latest views"].exists)
        keepScreenshot(app, named: "Smart Account overview")
        follow.tap()
        XCTAssertTrue(app.buttons["Tracking"].waitForExistence(timeout: 2))

        XCTAssertFalse(app.segmentedControls["smart.account.detail.section"].buttons["Views"].exists)
        for _ in 0..<5 {
            if app.descendants(matching: .any)["smart.account.latest-view.first"].isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.staticTexts["Latest views"].waitForExistence(timeout: 2))
        keepScreenshot(app, named: "Smart Account latest views")

        let evidence = app.descendants(matching: .any)["smart.account.latest-view.first"]
        XCTAssertTrue(evidence.waitForExistence(timeout: 2))
        evidence.tap()
        XCTAssertTrue(app.descendants(matching: .any)["smart.account.evidence.detail"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["Structured Call"].exists)
        XCTAssertTrue(app.staticTexts["Source evidence"].exists)
        keepScreenshot(app, named: "Smart Account evidence detail")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        for _ in 0..<10 {
            if app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "account.work.select.")).firstMatch.isHittable { break }
            app.swipeDown()
        }
        for _ in 0..<8 {
            if app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "account.work.select.")).firstMatch.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.staticTexts["Representative works"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["Top 3 tickers by cumulative Score contribution"].exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "account.work.select.")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Stock price change"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["account.work.chart"].exists)
        XCTAssertFalse(app.staticTexts["How to read this Score"].exists)
    }

    func testSmartMoneyOpensAuditableWalletAnalytics() {
        let app = launch(scenario: "loaded")

        tab(.smart, in: app).tap()
        XCTAssertTrue(app.descendants(matching: .any)["smart.screen"].waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Smart Money")).firstMatch.tap()

        let wallet = app.descendants(matching: .any)["smart.money.row.first"]
        XCTAssertTrue(wallet.waitForExistence(timeout: 3))
        keepScreenshot(app, named: "Smart Money cohort")
        wallet.tap()

        XCTAssertTrue(app.staticTexts["Current read"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Representative entries"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Representative market #1"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)["smart.money.representative-entry.0"].exists
        )
        XCTAssertTrue(app.staticTexts["Performance & risk"].exists)
        XCTAssertTrue(app.buttons["View original record"].exists)
        keepScreenshot(app, named: "Smart Money overview")

        app.buttons["Positions"].tap()
        XCTAssertTrue(app.staticTexts["Current positions"].waitForExistence(timeout: 2))

        app.buttons["Activity"].tap()
        XCTAssertTrue(app.staticTexts["Recent trades"].waitForExistence(timeout: 2))
    }

    func testTrackedSmartAccountAppearsInTodayActivityModule() {
        let app = launch(scenario: "loaded")

        tab(.smart, in: app).tap()
        let account = app.descendants(matching: .any)["smart.account.row.first"]
        XCTAssertTrue(account.waitForExistence(timeout: 4))
        account.tap()

        let track = app.buttons["smart.account.follow"]
        XCTAssertTrue(track.waitForExistence(timeout: 3))
        track.tap()
        XCTAssertTrue(app.buttons["Tracking"].waitForExistence(timeout: 2))

        app.buttons["detail.back"].tap()
        tab(.today, in: app).tap()

        let tracked = app.descendants(matching: .any)["today.tracked-activity"]
        for _ in 0..<10 where !tracked.exists {
            app.swipeUp()
        }
        XCTAssertTrue(tracked.waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Tracked activity"].exists)
        let trackedCard = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "today.tracked-activity.account:")
        ).firstMatch
        for _ in 0..<8 {
            if trackedCard.exists && trackedCard.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(trackedCard.waitForExistence(timeout: 4))
    }

    func testTrackedActivityOffersTopAccountsBeforeFollowingAnyone() {
        let app = launch(scenario: "loaded")
        let trackedTitle = app.staticTexts["Tracked activity"]
        for _ in 0..<10 {
            if trackedTitle.exists { break }
            app.swipeUp()
        }

        XCTAssertTrue(trackedTitle.waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Track top Smart Accounts"].exists)
        let recommendation = app.buttons["Track"].firstMatch
        XCTAssertTrue(recommendation.exists)
    }

    func testSmartPreviewsUseVisualTaxonomyInChinese() {
        let app = launch(scenario: "loaded", language: "zh-Hans")

        tab(.smart, in: app).tap()
        XCTAssertTrue(app.descendants(matching: .any)["smart.account.row.first"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Rank 1"].exists)
        XCTAssertTrue(app.staticTexts["半导体"].exists)
        XCTAssertTrue(app.staticTexts["中线"].exists)
        XCTAssertTrue(app.staticTexts["技术面"].exists)
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "N_eff")
        ).firstMatch.exists)
        keepScreenshot(app, named: "Smart Account visual preview zh-Hans")

    }

    func testSimplifiedChineseCoversCoreNavigationAndSmartDetails() {
        let app = launch(scenario: "loaded", language: "zh-Hans")

        XCTAssertTrue(app.staticTexts["今日"].waitForExistence(timeout: 5))
        XCTAssertEqual(tab(.smart, in: app).label, "Smart")
        tab(.smart, in: app).tap()

        XCTAssertTrue(app.descendants(matching: .any)["smart.screen"].waitForExistence(timeout: 5))
        let account = app.descendants(matching: .any)["smart.account.row.first"]
        XCTAssertTrue(account.waitForExistence(timeout: 3))
        account.tap()

        XCTAssertTrue(app.staticTexts["历史代表作"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["证据"].exists)
        XCTAssertTrue(app.buttons["方法"].exists)
        keepScreenshot(app, named: "Smart Account zh-Hans")

    }

    func testSimplifiedChineseCoversTodayPortfolioAndAllTickers() {
        let app = launch(scenario: "loaded", language: "zh-Hans")

        XCTAssertTrue(app.descendants(matching: .any)["today.screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["今日"].exists)
        XCTAssertTrue(app.staticTexts["聪明账户动态"].exists)
        XCTAssertFalse(app.buttons["today.scope.holdings"].exists)
        XCTAssertTrue(app.staticTexts["最值得查看"].exists)
        XCTAssertTrue(app.staticTexts["认为 HOOD 守住 US$93 后有机会回到 US$100"].exists)
        keepScreenshot(app, named: "Today zh-Hans")

        let lead = app.buttons["today.lead-activity"]
        XCTAssertTrue(lead.waitForExistence(timeout: 3))
        lead.tap()
        XCTAssertTrue(app.staticTexts["原观点证据"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["打开来源"].exists)
        keepScreenshot(app, named: "Today evidence zh-Hans")

        tab(.portfolio, in: app).tap()
        XCTAssertTrue(app.descendants(matching: .any)["portfolio.screen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["总收益"].exists)
        keepScreenshot(app, named: "Portfolio zh-Hans")

        app.buttons["全部标的"].tap()
        XCTAssertTrue(app.staticTexts["全部可检索标的"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.navigationBars["持仓"].exists)
        XCTAssertTrue(app.staticTexts["Bought long-term shares, bullish on AVGO."].exists)
        keepScreenshot(app, named: "Portfolio all tickers zh-Hans")
    }

    func testProfileAssistantUsesPortfolioEvidenceAndOpensEvent() {
        let app = launch(scenario: "loaded")

        XCTAssertTrue(app.descendants(matching: .any)["app.tabbar"].waitForExistence(timeout: 5))
        XCTAssertTrue(tab(.today, in: app).exists)
        XCTAssertTrue(tab(.portfolio, in: app).exists)
        XCTAssertTrue(app.buttons["app.tab.search"].exists)
        XCTAssertTrue(tab(.feed, in: app).exists)
        XCTAssertLessThan(app.buttons["app.tab.search"].frame.minX, tab(.portfolio, in: app).frame.minX)
        XCTAssertLessThan(app.buttons["app.tab.search"].frame.minX, tab(.feed, in: app).frame.minX)
        tab(.portfolio, in: app).tap()
        app.buttons["profile.ai.open"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["ai.screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Mr Collie"].exists)
        XCTAssertTrue(app.buttons["ai.new-conversation"].exists)
        XCTAssertTrue(app.staticTexts["What should we look into?"].exists)
        XCTAssertTrue(app.staticTexts["Suggested questions"].exists)

        let priority = app.buttons["Which position needs attention?"]
        XCTAssertTrue(priority.waitForExistence(timeout: 2))
        priority.tap()
        XCTAssertTrue(app.descendants(matching: .any)["ai.message.user"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["NVDA needs your attention"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Open event evidence"].waitForExistence(timeout: 2))
        app.buttons["Open event evidence"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["event-detail.screen"].waitForExistence(timeout: 3))
        app.buttons["detail.back"].tap()
        XCTAssertTrue(app.buttons["ai.back"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["app.tab.feed"].exists)
        app.buttons["ai.back"].tap()
        XCTAssertTrue(app.buttons["app.tab.feed"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["profile.ai.open"].isHittable)
    }

    func testAIComposerShowsTypedQuestionAndAnswerInConversation() {
        let app = launch(scenario: "loaded")
        tab(.portfolio, in: app).tap()
        app.buttons["profile.ai.open"].tap()

        let composer = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Message Mr Collie"))
            .firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["ai.send"].isEnabled)
        composer.tap()
        composer.typeText("What changed in NVDA?")
        app.buttons["Ask Mr Collie"].tap()

        XCTAssertTrue(app.staticTexts["What changed in NVDA?"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["NVDA needs your attention"].waitForExistence(timeout: 3))
        app.buttons["ai.new-conversation"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["ai.welcome"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["ai.send"].isEnabled)
        XCTAssertFalse(app.staticTexts["NVDA needs your attention"].exists)
    }

    func testAIChineseLightLayoutKeepsComposerVisibleWithLargeText() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-state", "--ui-scenario=loaded", "--ui-trading-fixture",
                               "--ui-appearance", "light", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"]
        app.launch()
        let profile = app.buttons["app.tab.portfolio"]
        XCTAssertTrue(profile.waitForExistence(timeout: 5))
        profile.tap()
        app.buttons["profile.ai.open"].tap()
        let composer = app.descendants(matching: .any)["ai.composer"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertTrue(composer.isHittable)
        XCTAssertGreaterThanOrEqual(composer.frame.minX, app.frame.minX + 12)
        XCTAssertLessThan(composer.frame.maxY, app.frame.maxY)
        XCTAssertGreaterThanOrEqual(app.buttons["ai.send"].frame.height, 44)
        let question = app.buttons["ai.prompt.priority"]
        for _ in 0..<3 where !question.isHittable { app.scrollViews["ai.timeline"].swipeUp() }
        XCTAssertTrue(question.isHittable)
        question.tap()
        XCTAssertTrue(app.descendants(matching: .any)["ai.message.assistant"].waitForExistence(timeout: 5))
        XCTAssertTrue(composer.isHittable)
        app.buttons["ai.back"].tap()
        XCTAssertTrue(app.buttons["app.tab.feed"].waitForExistence(timeout: 5))
    }

    func testFirstUseCanDiscoverTrackPreviewTradeAndOpenApp() {
        let app = launch(scenario: "first-use")

        XCTAssertTrue(app.descendants(matching: .any)["onboarding.screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.investor-pool"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.representative-work"].exists)
        app.buttons["onboarding.continue"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.latest-view"].waitForExistence(timeout: 3))
        app.buttons["onboarding.follow-featured"].tap()
        XCTAssertTrue(app.staticTexts["Tracking"].waitForExistence(timeout: 2))
        app.buttons["onboarding.continue"].tap()

        XCTAssertTrue(app.buttons["onboarding.trade-preview"].waitForExistence(timeout: 3))
        app.buttons["onboarding.trade-preview"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.order-preview"].waitForExistence(timeout: 3))
        app.buttons["Back to the opinion"].tap()
        app.buttons["onboarding.finish"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["today.screen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["app.tab.today"].waitForExistence(timeout: 3))
    }

    func testPortfolioAllTickersOpensIntelligenceWithUnifiedSmartActivity() {
        let app = launch(scenario: "loaded")

        tab(.portfolio, in: app).tap()
        XCTAssertTrue(app.descendants(matching: .any)["portfolio.screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Holdings"].isSelected)
        app.buttons["portfolio.tab.watchlist"].tap()
        XCTAssertTrue(app.buttons["portfolio.tab.watchlist"].isSelected)
        XCTAssertTrue(app.staticTexts["No watched tickers"].exists)
        app.buttons["All tickers"].tap()
        XCTAssertTrue(app.textFields["portfolio.ticker-search"].waitForExistence(timeout: 3))
        keepScreenshot(app, named: "Portfolio all tickers")

        let nvda = app.descendants(matching: .any)["portfolio.ticker.NVDA"]
        XCTAssertTrue(nvda.waitForExistence(timeout: 3))
        nvda.tap()

        XCTAssertTrue(app.descendants(matching: .any)["ticker-intelligence.NVDA"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["ticker-intelligence.price-activity"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["ticker-intelligence.smart-activity"].exists)
        XCTAssertTrue(app.buttons["Smart Activity"].exists)
        XCTAssertTrue(app.staticTexts["Smart Account"].exists)
        XCTAssertFalse(app.staticTexts["Current relationship"].exists)
        keepScreenshot(app, named: "Ticker intelligence overview")

        let activityTab = app.buttons["Smart Activity"]
        XCTAssertTrue(activityTab.isHittable)
        activityTab.tap()
        XCTAssertTrue(app.descendants(matching: .any)["ticker-intelligence.smart-activity"].waitForExistence(timeout: 2))
        keepScreenshot(app, named: "Ticker intelligence Smart Activity")

        let overviewTab = app.buttons["Overview"]
        XCTAssertTrue(overviewTab.isHittable)
        overviewTab.tap()
        XCTAssertTrue(app.descendants(matching: .any)["ticker-intelligence.price-activity"].waitForExistence(timeout: 2))
    }

    func testPortfolioEntryOpensIntelligenceAndKeepsNativeEditorAvailable() {
        let app = launch(scenario: "loaded")

        tab(.portfolio, in: app).tap()
        XCTAssertTrue(app.descendants(matching: .any)["portfolio.screen"].waitForExistence(timeout: 5))

        let hood = app.buttons["portfolio.entry.HOOD"]
        XCTAssertTrue(hood.waitForExistence(timeout: 3))
        hood.tap()

        XCTAssertTrue(app.descendants(matching: .any)["ticker-intelligence.HOOD"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["ticker-intelligence.price-activity"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Smart Activity"].exists)
        XCTAssertFalse(app.staticTexts["Current relationship"].exists)
        let detailBack = app.buttons["detail.back"]
        XCTAssertTrue(detailBack.waitForExistence(timeout: 2))
        detailBack.tap()
        XCTAssertTrue(app.descendants(matching: .any)["app.tabbar"].exists)

        let entry = app.buttons["portfolio.entry.HOOD"]
        XCTAssertTrue(entry.waitForExistence(timeout: 3))
        entry.press(forDuration: 1)
        let edit = app.buttons["Edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 2))
        edit.tap()

        XCTAssertTrue(app.descendants(matching: .any)["position-editor.screen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.navigationBars["Edit HOOD"].exists)
        XCTAssertTrue(app.buttons["Save"].exists)
    }

    func testReadOnlyBrokeragePrototypeReviewsAndImportsSupportedHoldings() {
        let app = launch(scenario: "loaded")

        tab(.portfolio, in: app).tap()
        XCTAssertTrue(app.descendants(matching: .any)["portfolio.screen"].waitForExistence(timeout: 5))
        app.buttons["portfolio.brokerage-connections"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["brokerage-connections.screen"].waitForExistence(timeout: 3))
        app.buttons["brokerage.provider.robinhood"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["brokerage-setup.robinhood"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Cannot place trades or withdraw funds"].exists)

        app.buttons["brokerage.preview-authorization"].tap()
        XCTAssertTrue(app.staticTexts["Authorization preview complete"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["BTC"].exists)
        XCTAssertTrue(app.staticTexts["Preview only"].exists)
        keepScreenshot(app, named: "Brokerage holdings preview")

        app.buttons["brokerage.finish-prototype"].tap()
        XCTAssertTrue(app.staticTexts["Read-only prototype linked"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["2"].exists)
    }

    func testSettingsNoLongerExposeNotificationPreferences() {
        let app = launch(scenario: "loaded")

        XCTAssertFalse(app.staticTexts["DEMO"].exists)
        tab(.portfolio, in: app).tap()
        let openSettings = app.buttons["portfolio.settings"]
        XCTAssertTrue(openSettings.waitForExistence(timeout: 5))
        openSettings.tap()

        XCTAssertTrue(app.descendants(matching: .any)["settings.screen"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["settings.notifications"].exists)
        XCTAssertTrue(app.buttons["settings.language.en"].exists)
    }

    func testTodayDoesNotSurfaceGenericOpportunityRadar() {
        let app = launch(scenario: "loaded")

        XCTAssertTrue(app.descendants(matching: .any)["today.screen"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["today.opportunity-radar"].exists)
    }

    func testSettingsDoNotExposeLocalDataReset() {
        let app = launch(scenario: "loaded")

        tab(.portfolio, in: app).tap()
        XCTAssertTrue(app.descendants(matching: .any)["portfolio.screen"].waitForExistence(timeout: 5))
        app.buttons["Open settings"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["settings.screen"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["settings.reset-local-data"].exists)
    }

    func testSettingsRemoveDataPrivacyGroupAndKeepFeedback() {
        let app = launch(scenario: "loaded")

        tab(.portfolio, in: app).tap()
        XCTAssertTrue(app.descendants(matching: .any)["portfolio.screen"].waitForExistence(timeout: 5))
        app.buttons["Open settings"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["settings.screen"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["settings.data-methodology"].exists)
        XCTAssertFalse(app.buttons["settings.risk-disclosure"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["settings.send-feedback"].exists)
    }

    func testLanguageCanSwitchImmediatelyInsideSettings() {
        let app = launch(scenario: "loaded")

        tab(.portfolio, in: app).tap()
        XCTAssertTrue(app.descendants(matching: .any)["portfolio.screen"].waitForExistence(timeout: 5))
        app.buttons["Open settings"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["settings.screen"].waitForExistence(timeout: 3))
        let chinese = app.buttons["settings.language.zh-Hans"]
        XCTAssertTrue(chinese.waitForExistence(timeout: 2))
        chinese.tap()

        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["完成"].exists)
        XCTAssertTrue(chinese.isSelected)
        keepScreenshot(app, named: "Language settings zh-Hans")

        app.buttons["完成"].tap()
        XCTAssertTrue(app.navigationBars["持仓"].waitForExistence(timeout: 3))
        XCTAssertTrue(tab(.portfolio, in: app).exists)
        app.buttons["portfolio.settings"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings.screen"].waitForExistence(timeout: 3))

        let english = app.buttons["settings.language.en"]
        english.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Done"].exists)
        XCTAssertTrue(english.isSelected)
        keepScreenshot(app, named: "Language settings en")
    }

    func testLightAppearanceCoversCoreScreensAndSheets() {
        let app = launch(scenario: "loaded", appearance: "light")

        XCTAssertTrue(app.descendants(matching: .any)["today.screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["discovery.open-directory"].isHittable)

        tab(.portfolio, in: app).tap()
        let settings = app.buttons["portfolio.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        settings.tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings.screen"].waitForExistence(timeout: 3))
        let lightAppearance = app.buttons["settings.appearance.light"]
        XCTAssertTrue(lightAppearance.waitForExistence(timeout: 2))
        XCTAssertTrue(lightAppearance.isSelected)
        app.buttons["Done"].tap()

        tab(.today, in: app).tap()
        app.buttons["discovery.open-directory"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["smart.screen"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["app.tab.today"].isHittable)
        let filters = app.buttons["smart.account.filters"]
        XCTAssertTrue(filters.waitForExistence(timeout: 2))
        filters.tap()
        XCTAssertTrue(app.navigationBars["Filters"].waitForExistence(timeout: 2))
        app.buttons["Done"].tap()
        app.buttons["detail.back"].tap()
        XCTAssertTrue(app.buttons["app.tab.today"].waitForExistence(timeout: 3))

        tab(.portfolio, in: app).tap()
        XCTAssertTrue(app.descendants(matching: .any)["portfolio.screen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["portfolio.deposit"].isHittable)
        XCTAssertTrue(app.buttons["portfolio.withdraw"].isHittable)
        tab(.feed, in: app).tap()
        XCTAssertTrue(app.buttons["discover.tab.popular"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["discover.tab.popular"].isSelected)
        XCTAssertTrue(app.buttons["discover.tab.latest"].isHittable)
        app.buttons["app.tab.search"].tap()
        XCTAssertTrue(app.textFields["search.input"].waitForExistence(timeout: 5))

    }

    private func keepScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tab(_ section: AppTab, in app: XCUIApplication) -> XCUIElement {
        let byIdentifier = app.descendants(matching: .any)["app.tab.\(section.rawValue)"]
        if byIdentifier.exists {
            return byIdentifier
        }

        let labels: [String]
        switch section {
        case .today:
            labels = ["Today", "今日"]
        case .portfolio:
            labels = ["Portfolio", "持仓"]
        case .smart:
            labels = ["Smart"]
        case .feed:
            labels = ["Feed"]
        }

        for label in labels where app.buttons[label].exists {
            return app.buttons[label]
        }
        return app.buttons[labels[0]]
    }

    private func launch(
        scenario: String,
        language: String? = nil,
        appearance: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        let resolvedLanguage = language ?? "en"
        let resolvedLocale = language == nil ? "en_US" : "zh_CN"
        app.launchArguments = [
            "--ui-reset-state",
            "--ui-scenario=\(scenario)",
            "--ui-trading-fixture",
            "-AppleLanguages", "(\(resolvedLanguage))",
            "-AppleLocale", resolvedLocale
        ]
        if let appearance {
            app.launchArguments += ["--ui-appearance", appearance]
        }
        app.launch()
        return app
    }
}

private enum AppTab: String {
    case today
    case smart
    case portfolio
    case feed
}
