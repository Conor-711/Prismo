import XCTest

final class BSmartUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLoadedPortfolioOpensTodayWithoutBlockingLoader() {
        let app = launch(scenario: "loaded")

        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["today.portfolio-now"].exists)
        XCTAssertFalse(app.buttons["today.scope.holdings"].exists)
        XCTAssertTrue(app.staticTexts["Latest update"].exists)
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "published a")
        ).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Loading your portfolio"].exists)
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

        XCTAssertTrue(app.descendants(matching: .any)["today.portfolio-now"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["today.scope.holdings"].exists)
        XCTAssertFalse(app.buttons["today.scope.watchlist"].exists)
        XCTAssertTrue(app.buttons["today.chart-style.line"].isSelected)

        app.swipeUp()
        app.swipeUp()

        let package = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "today.viewpoint-package.")
        ).firstMatch
        XCTAssertTrue(package.waitForExistence(timeout: 3))
        keepScreenshot(app, named: "Today editorial collections")
        package.tap()

        let back = app.buttons["today.viewpoint-package.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 4))
        XCTAssertFalse(app.navigationBars["NVDA"].exists)
        XCTAssertTrue(app.staticTexts["聪明共识"].exists)
        XCTAssertTrue(app.staticTexts["核心 Smart Account"].exists)
        let leadingAccount = app.descendants(matching: .any)["today.consensus-leading-account.0"]
        XCTAssertTrue(leadingAccount.exists)
        leadingAccount.tap()
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

    func testTodaySmartAlphaOpensDedicatedEvidencePage() {
        let app = launch(scenario: "loaded", language: "zh-Hans")

        XCTAssertTrue(app.descendants(matching: .any)["today.portfolio-now"].waitForExistence(timeout: 5))
        let alphaCard = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "today.smart-alpha.")
        ).firstMatch

        for _ in 0..<7 {
            if alphaCard.exists && alphaCard.isHittable { break }
            app.swipeUp()
        }

        XCTAssertTrue(alphaCard.waitForExistence(timeout: 3))
        XCTAssertTrue(alphaCard.isHittable)
        keepScreenshot(app, named: "Today Smart Alpha module")
        alphaCard.tap()

        XCTAssertTrue(app.buttons["today.smart-alpha.back"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["聪明阿尔法"].exists)
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
        keepScreenshot(app, named: "Today Smart Alpha detail")
        app.buttons["today.smart-alpha.back"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["app.tabbar"].exists)
    }

    func testTodayRepresentativeViewOpensViewDetailInsteadOfAccountProfile() {
        let app = launch(scenario: "loaded")
        let deck = app.descendants(matching: .any)["today.interlude-deck"].firstMatch
        for _ in 0..<6 {
            if deck.exists && deck.isHittable { break }
            app.swipeUp()
        }

        XCTAssertTrue(deck.waitForExistence(timeout: 4))
        deck.swipeUp()
        deck.swipeUp()

        let representativeView = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "today.interlude.account-view-")
        ).firstMatch
        XCTAssertTrue(representativeView.waitForExistence(timeout: 3))
        representativeView.tap()

        XCTAssertTrue(app.descendants(matching: .any)["smart.account.evidence.detail"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["smart.account.trust-preview"].exists)
    }

    func testTodayStandaloneViewsAreCappedAndOpenAFullPage() {
        let app = launch(scenario: "loaded", language: "zh-Hans")

        let viewAll = app.buttons["today.standalone.view-all"]
        for _ in 0..<10 {
            if viewAll.exists && viewAll.isHittable { break }
            app.swipeUp()
        }

        XCTAssertTrue(viewAll.exists)
        XCTAssertTrue(viewAll.isHittable)
        keepScreenshot(app, named: "Today Smart Money before standalone views")
        viewAll.tap()

        XCTAssertTrue(app.descendants(matching: .any)["today.standalone.full-list"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.navigationBars["单独观点"].exists)
        keepScreenshot(app, named: "Today all standalone views")
    }

    func testTodayPriceChartSwitchesModeAndOpensAvatarEvidence() {
        let app = launch(scenario: "loaded", language: "zh-Hans")

        XCTAssertTrue(app.descendants(matching: .any)["today.portfolio-now"].waitForExistence(timeout: 5))
        let line = app.buttons["today.chart-style.line"]
        XCTAssertTrue(line.exists)
        line.tap()
        XCTAssertTrue(line.isSelected)
        keepScreenshot(app, named: "Today price evidence hero")

        let marker = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "today.price-marker.")
        ).firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 3))
        let visibleMarkers = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "today.price-marker.")
        )
        XCTAssertGreaterThan(visibleMarkers.count, 0)
        XCTAssertLessThanOrEqual(visibleMarkers.count, 5)
        XCTAssertTrue(marker.label.contains("Top") || marker.label.contains("#"))

        app.buttons["today.chart-period"].tap()
        app.buttons["7D"].tap()
        XCTAssertLessThanOrEqual(visibleMarkers.count, 3)

        app.buttons["today.chart-period"].tap()
        app.buttons["3M"].tap()
        XCTAssertLessThanOrEqual(visibleMarkers.count, 7)
        marker.tap()

        XCTAssertTrue(app.navigationBars["价格证据"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["app.tabbar"].exists)
        keepScreenshot(app, named: "Today interactive price avatar evidence")
        let detailBack = app.buttons["detail.back"]
        XCTAssertTrue(detailBack.waitForExistence(timeout: 2))
        detailBack.tap()
        XCTAssertTrue(app.descendants(matching: .any)["app.tabbar"].exists)
    }

    func testWeightOnlyPortfolioUsesMonitoringSummaryInsteadOfZeroValue() {
        let app = launch(scenario: "weight-only")

        XCTAssertTrue(app.descendants(matching: .any)["today.portfolio-now"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Latest update"].exists)
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
        XCTAssertTrue(app.staticTexts["AI recent summary"].exists)
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

        app.buttons["Views"].tap()
        XCTAssertTrue(app.staticTexts["Latest views"].waitForExistence(timeout: 2))
        keepScreenshot(app, named: "Smart Account latest views")

        let evidence = app.descendants(matching: .any)["smart.account.latest-view.first"]
        XCTAssertTrue(evidence.waitForExistence(timeout: 2))
        evidence.tap()
        XCTAssertTrue(app.descendants(matching: .any)["smart.account.evidence.detail"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Structured Call"].exists)
        XCTAssertTrue(app.staticTexts["Source evidence"].exists)
        keepScreenshot(app, named: "Smart Account evidence detail")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["Track record"].tap()
        XCTAssertTrue(app.staticTexts["Representative works"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["Top 3 tickers by cumulative Score contribution"].exists)
        XCTAssertTrue(app.staticTexts["Representative ticker #1"].exists)
        XCTAssertTrue(app.staticTexts["Score contribution"].exists)
        XCTAssertTrue(app.otherElements["smart.account.representative-work.0"].exists)
        XCTAssertFalse(app.staticTexts["How to read this Score"].exists)
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
        XCTAssertTrue(app.staticTexts["Representative market #1"].exists)
        XCTAssertTrue(app.otherElements["smart.money.representative-entry.0"].exists)
        XCTAssertTrue(app.staticTexts["Performance & risk"].exists)
        XCTAssertTrue(app.buttons["View original record"].exists)
        keepScreenshot(app, named: "Smart Money overview")

        app.buttons["Positions"].tap()
        XCTAssertTrue(app.staticTexts["Current positions"].waitForExistence(timeout: 2))
        keepScreenshot(app, named: "Smart Money positions")

        app.buttons["Activity"].tap()
        XCTAssertTrue(app.staticTexts["Recent trades"].waitForExistence(timeout: 2))
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

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Smart Money")).firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["smart.money.row.first"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["AI 基础设施"].exists)
        XCTAssertTrue(app.staticTexts["偏多风格"].exists)
        keepScreenshot(app, named: "Smart Money visual preview zh-Hans")
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

        app.navigationBars["Smart Account"].buttons.firstMatch.tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Smart Money")).firstMatch.tap()
        let wallet = app.descendants(matching: .any)["smart.money.row.first"]
        XCTAssertTrue(wallet.waitForExistence(timeout: 3))
        wallet.tap()

        XCTAssertTrue(app.staticTexts["当前判断"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["持仓"].exists)
        XCTAssertTrue(app.buttons["动态"].exists)
        keepScreenshot(app, named: "Smart Money zh-Hans")
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

    func testAITabUsesPortfolioEvidenceAndOpensEvent() {
        let app = launch(scenario: "loaded")

        XCTAssertTrue(app.descendants(matching: .any)["app.tabbar"].waitForExistence(timeout: 5))
        XCTAssertTrue(tab(.today, in: app).exists)
        XCTAssertTrue(tab(.portfolio, in: app).exists)
        XCTAssertTrue(tab(.smart, in: app).exists)
        XCTAssertTrue(tab(.ai, in: app).exists)
        XCTAssertLessThan(tab(.portfolio, in: app).frame.minX, tab(.smart, in: app).frame.minX)
        XCTAssertFalse(app.buttons["Tickers"].exists)
        tab(.ai, in: app).tap()

        XCTAssertTrue(app.descendants(matching: .any)["ai.screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Mr Collie"].exists)
        XCTAssertTrue(app.staticTexts["Portfolio intelligence"].exists)
        XCTAssertTrue(app.staticTexts["What should we look into?"].exists)
        XCTAssertTrue(app.staticTexts["Suggested questions"].exists)
        keepScreenshot(app, named: "AI portfolio assistant")

        let priority = app.buttons["Which position needs attention?"]
        XCTAssertTrue(priority.waitForExistence(timeout: 2))
        priority.tap()
        XCTAssertTrue(app.descendants(matching: .any)["ai.message.user"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["NVDA needs your attention"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Open event evidence"].waitForExistence(timeout: 2))
        app.buttons["Open event evidence"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["event-detail.screen"].waitForExistence(timeout: 3))
    }

    func testAIComposerShowsTypedQuestionAndAnswerInConversation() {
        let app = launch(scenario: "loaded")
        tab(.ai, in: app).tap()

        let composer = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Message Mr Collie"))
            .firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        composer.tap()
        composer.typeText("What changed in NVDA?")
        app.buttons["Ask Mr Collie"].tap()

        XCTAssertTrue(app.staticTexts["What changed in NVDA?"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["NVDA needs your attention"].waitForExistence(timeout: 3))
    }

    func testAIComposerFocusesPromptlyAndDismissesFromConversation() {
        let app = launch(scenario: "loaded")
        tab(.ai, in: app).tap()

        let composer = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Message Mr Collie"))
            .firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        composer.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 1))

        app.staticTexts["Mr Collie"].firstMatch.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 2))
    }

    func testTodayActivityCanFilterIndependentSourcesAndUnreadState() {
        let app = launch(scenario: "loaded")

        let money = app.buttons["today.filter.money"]
        for _ in 0..<5 where !money.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(money.waitForExistence(timeout: 3))
        money.tap()
        XCTAssertTrue(money.isSelected)
        XCTAssertFalse(app.staticTexts["Views and capital agree"].exists)
        XCTAssertFalse(app.staticTexts["Views and capital diverge"].exists)

        let unread = app.buttons["today.filter.unread"]
        for _ in 0..<3 where !unread.isHittable {
            app.swipeRight()
        }
        XCTAssertTrue(unread.waitForExistence(timeout: 2))
        unread.tap()
        XCTAssertTrue(unread.isSelected)

        let sortMenu = app.buttons["today.sort.menu"]
        XCTAssertTrue(sortMenu.isHittable)
        sortMenu.tap()
        let smartScore = app.buttons["Smart score"]
        XCTAssertTrue(smartScore.waitForExistence(timeout: 2))
        smartScore.tap()
        XCTAssertTrue(app.staticTexts["Highest Smart score"].waitForExistence(timeout: 2))
    }

    func testFirstUseCanConnectBrokerageFollowAccountAndOpenPersonalFeed() {
        let app = launch(scenario: "first-use")

        XCTAssertTrue(app.descendants(matching: .any)["onboarding.screen"].waitForExistence(timeout: 5))
        app.buttons["onboarding.continue"].tap()
        XCTAssertTrue(app.staticTexts["See bSmart in action"].waitForExistence(timeout: 3))
        keepScreenshot(app, named: "Onboarding product examples")
        app.buttons["onboarding.continue"].tap()

        let connectBrokerage = app.buttons["onboarding.connect-brokerage"]
        XCTAssertTrue(connectBrokerage.waitForExistence(timeout: 3))
        connectBrokerage.tap()

        XCTAssertTrue(app.descendants(matching: .any)["brokerage-connections.screen"].waitForExistence(timeout: 3))
        app.buttons["brokerage.provider.robinhood"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["brokerage-setup.robinhood"].waitForExistence(timeout: 3))
        app.buttons["brokerage.preview-authorization"].tap()
        XCTAssertTrue(app.staticTexts["Authorization preview complete"].waitForExistence(timeout: 3))
        app.buttons["brokerage.finish-prototype"].tap()
        XCTAssertTrue(connectBrokerage.waitForExistence(timeout: 3))
        keepScreenshot(app, named: "Onboarding connect and track")

        let followAccount = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "onboarding.follow-account."))
            .firstMatch
        XCTAssertTrue(followAccount.waitForExistence(timeout: 3))
        for _ in 0..<3 where !followAccount.isHittable {
            app.swipeUp()
        }
        followAccount.tap()

        let finishButton = app.buttons["onboarding.finish"]
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: finishButton)
        waitForExpectations(timeout: 2)
        finishButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["today.screen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["today.portfolio-snapshot.nvda"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["today.scope.watchlist"].exists)
    }

    func testPortfolioAllTickersOpensIntelligenceWithUnifiedSmartActivity() {
        let app = launch(scenario: "loaded")

        tab(.portfolio, in: app).tap()
        XCTAssertTrue(app.descendants(matching: .any)["portfolio.screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Holdings"].isSelected)
        app.buttons["Watchlist"].tap()
        XCTAssertTrue(app.buttons["Watchlist"].isSelected)
        XCTAssertTrue(app.staticTexts["No watched tickers"].exists)
        app.buttons["All tickers"].tap()
        XCTAssertTrue(app.staticTexts["All supported tickers"].waitForExistence(timeout: 3))
        keepScreenshot(app, named: "Portfolio all tickers")

        let nvda = app.descendants(matching: .any)["portfolio.ticker.NVDA"]
        XCTAssertTrue(nvda.waitForExistence(timeout: 3))
        nvda.tap()

        XCTAssertTrue(app.descendants(matching: .any)["ticker-intelligence.NVDA"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["ticker-intelligence.price-activity"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["ticker-intelligence.smart-activity"].exists)
        XCTAssertTrue(app.buttons["Smart Activity"].exists)
        XCTAssertTrue(app.staticTexts["Smart Account"].exists)
        XCTAssertTrue(app.staticTexts["Smart Money"].exists)
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

    func testAlertSettingsExposeScheduleAndPerTickerControls() {
        let app = launch(scenario: "loaded")

        XCTAssertFalse(app.staticTexts["DEMO"].exists)
        let openSettings = app.buttons["today.settings"]
        XCTAssertTrue(openSettings.waitForExistence(timeout: 5))
        openSettings.tap()

        XCTAssertTrue(app.descendants(matching: .any)["settings.screen"].waitForExistence(timeout: 3))
        app.buttons["settings.notifications"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["alerts.screen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Delivery time"].exists)
        XCTAssertTrue(app.staticTexts["Quiet hours"].exists)

        let nvdaAlerts = app.switches["alerts.ticker.NVDA"]
        XCTAssertTrue(nvdaAlerts.waitForExistence(timeout: 2))
        for _ in 0..<3 where !nvdaAlerts.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(nvdaAlerts.isHittable)
        XCTAssertEqual(nvdaAlerts.value as? String, "1")
        nvdaAlerts.tap()
        XCTAssertEqual(nvdaAlerts.value as? String, "0")
    }

    func testTodayDoesNotSurfaceGenericOpportunityRadar() {
        let app = launch(scenario: "loaded")

        XCTAssertTrue(app.descendants(matching: .any)["today.screen"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["today.opportunity-radar"].exists)
    }

    func testLocalDataResetReturnsToPortfolioSetup() {
        let app = launch(scenario: "loaded")

        tab(.portfolio, in: app).tap()
        XCTAssertTrue(app.descendants(matching: .any)["portfolio.screen"].waitForExistence(timeout: 5))
        app.buttons["Open settings"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["settings.screen"].waitForExistence(timeout: 3))
        app.descendants(matching: .any)["settings.reset-local-data"].tap()
        app.buttons["Reset local app data"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["onboarding.screen"].waitForExistence(timeout: 3))
    }

    func testSettingsExposeDemoMethodologyAndRiskLimits() {
        let app = launch(scenario: "loaded")

        tab(.portfolio, in: app).tap()
        XCTAssertTrue(app.descendants(matching: .any)["portfolio.screen"].waitForExistence(timeout: 5))
        app.buttons["Open settings"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["settings.screen"].waitForExistence(timeout: 3))
        app.buttons["settings.data-methodology"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["methodology.screen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["This build uses demonstration evidence and events."].exists)
        XCTAssertTrue(app.staticTexts["Smart Account"].exists)
        XCTAssertTrue(app.staticTexts["Smart Money"].exists)

        app.navigationBars["Data & methodology"].buttons.firstMatch.tap()
        app.buttons["settings.risk-disclosure"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["risk-disclosure.screen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Score limitations"].exists)
        XCTAssertTrue(app.staticTexts["Market risk"].exists)
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
        keepScreenshot(app, named: "Light appearance - Today")

        let settings = app.buttons["today.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        settings.tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings.screen"].waitForExistence(timeout: 3))
        let lightAppearance = app.buttons["settings.appearance.light"]
        XCTAssertTrue(lightAppearance.waitForExistence(timeout: 2))
        XCTAssertTrue(lightAppearance.isSelected)
        keepScreenshot(app, named: "Light appearance - Settings")
        app.buttons["Done"].tap()

        tab(.smart, in: app).tap()
        XCTAssertTrue(app.descendants(matching: .any)["smart.screen"].waitForExistence(timeout: 3))
        keepScreenshot(app, named: "Light appearance - Smart")
        let filters = app.buttons["Filters"]
        XCTAssertTrue(filters.waitForExistence(timeout: 2))
        filters.tap()
        XCTAssertTrue(app.navigationBars["Filters"].waitForExistence(timeout: 2))
        keepScreenshot(app, named: "Light appearance - Smart filters")
        app.buttons["Done"].tap()

        tab(.portfolio, in: app).tap()
        XCTAssertTrue(app.descendants(matching: .any)["portfolio.screen"].waitForExistence(timeout: 3))
        keepScreenshot(app, named: "Light appearance - Portfolio")

        tab(.ai, in: app).tap()
        XCTAssertTrue(app.descendants(matching: .any)["ai.screen"].waitForExistence(timeout: 3))
        keepScreenshot(app, named: "Light appearance - Mr Collie")
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
        case .ai:
            labels = ["Mr Collie"]
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
    case ai
}
