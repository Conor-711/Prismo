import SwiftUI

/// Zoom transitions can detach SwiftUI content before the presented controller disappears.
struct BSmartDetailVisibilityObserver: UIViewControllerRepresentable {
    let router: AppRouter
    let token: UUID

    func makeUIViewController(context: Context) -> BSmartDetailVisibilityController {
        BSmartDetailVisibilityController(router: router, token: token)
    }

    func updateUIViewController(_ controller: BSmartDetailVisibilityController, context: Context) {}

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

    init(router: AppRouter, token: UUID) {
        self.router = router
        self.token = token
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
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        router.setTabBarHidden(false, token: token)
    }
}
