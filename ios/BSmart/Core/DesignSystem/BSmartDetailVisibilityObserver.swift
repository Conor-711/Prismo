import SwiftUI

/// Tracks native navigation visibility independently of SwiftUI view removal.
struct BSmartDetailVisibilityObserver: UIViewControllerRepresentable {
    let router: AppRouter
    let token: UUID
    var allowsBack = true

    func makeUIViewController(context: Context) -> BSmartDetailVisibilityController {
        BSmartDetailVisibilityController(router: router, token: token, allowsBack: allowsBack)
    }

    func updateUIViewController(_ controller: BSmartDetailVisibilityController, context: Context) {
        controller.allowsBack = allowsBack
    }

    static func dismantleUIViewController(_ controller: BSmartDetailVisibilityController, coordinator: ()) {
        // Let SwiftUI finish removing the view before publishing router changes.
        Task { @MainActor [router = controller.router, token = controller.token] in
            router.setTabBarHidden(false, token: token)
        }
    }
}

final class BSmartDetailVisibilityController: UIViewController {
    let router: AppRouter
    let token: UUID
    var allowsBack: Bool {
        didSet {
            if oldValue != allowsBack, viewIfLoaded?.window != nil {
                restoreEdgeBackForCurrentPage()
            }
        }
    }

    init(router: AppRouter, token: UUID, allowsBack: Bool = true) {
        self.router = router
        self.token = token
        self.allowsBack = allowsBack
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = UIView()
        view.isUserInteractionEnabled = false
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        router.setTabBarHidden(true, token: token)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        router.setTabBarHidden(true, token: token)
        restoreEdgeBackForCurrentPage()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // SwiftUI can reset the recognizer after applying its hidden back item.
        if view.window != nil, navigationController?.transitionCoordinator == nil {
            restoreEdgeBackForCurrentPage()
        }
    }

    func restoreEdgeBackForCurrentPage() {
        guard let navigationController, let top = navigationController.topViewController else { return }
        // A retained parent page must not override the current page's protected workflow.
        var ancestor: UIViewController? = self
        while let current = ancestor {
            if current === top {
                BSmartEdgeBackNavigation.enable(on: navigationController, allowsBack: allowsBack)
                return
            }
            ancestor = current.parent
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        router.setTabBarHidden(false, token: token)
    }
}
