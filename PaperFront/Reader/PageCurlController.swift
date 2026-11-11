import UIKit
import PDFKit
import SwiftUI

/// Hosts a `UIPageViewController` with the system page-curl transition — the same
/// physics Apple Books uses. Landscape iPads get a real two-page spread.
final class PageCurlController: UIViewController, UIPageViewControllerDataSource,
                                UIPageViewControllerDelegate, UIGestureRecognizerDelegate {
    private unowned let model: ReaderModel
    private var pageVC: UIPageViewController?
    private var twoPage = false
    var isTwoPage: Bool { twoPage }
    private(set) var currentIndex = 0
    private var config = ReaderConfig()

    init(model: ReaderModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
        currentIndex = model.currentPage
        config = model.config
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var pageCount: Int { model.document.pageCount }
    private var virtualCount: Int { twoPage && pageCount % 2 == 1 ? pageCount + 1 : pageCount }
    private var step: Int { twoPage ? 2 : 1 }
    private var paper: UIColor { config.night ? Mocha.baseUI : .white }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Mocha.crustUI
        let tap = UITapGestureRecognizer(target: self, action: #selector(centerTap(_:)))
        tap.delegate = self
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        model.annotations.onHighlightsChanged = { [weak self] in
            self?.visiblePages.forEach { $0.refreshHighlights() }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = view.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        let wantTwo = size.width > size.height * 1.2 && size.height >= 600
        if pageVC == nil || wantTwo != twoPage {
            twoPage = wantTwo
            rebuild()
        }
    }

    // MARK: Building

    private var visiblePages: [PageContentViewController] {
        (pageVC?.viewControllers ?? []).compactMap { $0 as? PageContentViewController }
    }

    private func rebuild() {
        if let old = pageVC {
            old.willMove(toParent: nil)
            old.view.removeFromSuperview()
            old.removeFromParent()
        }
        let location: UIPageViewController.SpineLocation = twoPage ? .mid : .min
        let pvc = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: [.spineLocation: location.rawValue]
        )
        pvc.isDoubleSided = twoPage
        pvc.dataSource = self
        pvc.delegate = self
        addChild(pvc)
        pvc.view.frame = view.bounds
        pvc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        pvc.view.backgroundColor = paper
        view.addSubview(pvc.view)
        pvc.didMove(toParent: self)
        pageVC = pvc
        setSpread(at: currentIndex, animated: false, forward: true)
        applyGestureState()
    }

    private func spine(for index: Int) -> SpineSide {
        guard twoPage else { return .left }
        return index % 2 == 0 ? .right : .left
    }

    private func makePage(_ index: Int) -> UIViewController {
        if index < pageCount, let page = model.document.page(at: index) {
            return PageContentViewController(index: index, page: page, model: model, config: config, spine: spine(for: index))
        }
        return BlankPageViewController(index: index, paper: paper)
    }

    private func setSpread(at index: Int, animated: Bool, forward: Bool) {
        guard pageCount > 0, let pvc = pageVC else { return }
        let clamped = min(max(index, 0), pageCount - 1)
        let first = twoPage ? clamped & ~1 : clamped
        let indices = twoPage ? [first, first + 1] : [first]
        pvc.setViewControllers(
            indices.map(makePage),
            direction: forward ? .forward : .reverse,
            animated: animated
        )
        currentIndex = first
        model.pageDidChange(first)
    }

    // MARK: Public API

    func apply(config newConfig: ReaderConfig) {
        guard newConfig != config else { return }
        config = newConfig
        pageVC?.view.backgroundColor = paper
        visiblePages.forEach { $0.config = newConfig }
        applyGestureState()
    }

    func goTo(_ index: Int, animated: Bool = true) {
        let target = min(max(index, 0), max(pageCount - 1, 0))
        setSpread(at: target, animated: animated, forward: target >= currentIndex)
    }

    func next() { if currentIndex + step < pageCount { goTo(currentIndex + step) } }
    func previous() { if currentIndex > 0 { goTo(currentIndex - step) } }

    /// Rebuild from scratch (after the document was replaced).
    func reload() {
        PageRenderer.flush()
        rebuild()
    }

    var canUndo: Bool { visiblePages.contains { $0.canUndo } }
    var canRedo: Bool { visiblePages.contains { $0.canRedo } }
    func undo() { visiblePages.first { $0.canUndo }?.undo() }
    func redo() { visiblePages.first { $0.canRedo }?.redo() }

    /// Page-curl swipes would fight with highlighting and drawing, so they're only live in read mode.
    private func applyGestureState() {
        pageVC?.gestureRecognizers.forEach { $0.isEnabled = (config.mode == .read) }
    }

    // MARK: Gestures

    @objc private func centerTap(_ g: UITapGestureRecognizer) {
        guard config.mode == .read else { return }
        let x = g.location(in: view).x / max(view.bounds.width, 1)
        if x > 0.28 && x < 0.72 { model.chromeVisible.toggle() }
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    // MARK: UIPageViewControllerDataSource

    private func index(of vc: UIViewController) -> Int? { (vc as? IndexedPage)?.pageIndex }

    func pageViewController(_ pvc: UIPageViewController, viewControllerBefore vc: UIViewController) -> UIViewController? {
        guard let i = index(of: vc), i > 0 else { return nil }
        return makePage(i - 1)
    }

    func pageViewController(_ pvc: UIPageViewController, viewControllerAfter vc: UIViewController) -> UIViewController? {
        guard let i = index(of: vc), i + 1 < virtualCount else { return nil }
        return makePage(i + 1)
    }

    // MARK: UIPageViewControllerDelegate

    func pageViewController(_ pvc: UIPageViewController, didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard completed, let first = pvc.viewControllers?.compactMap({ index(of: $0) }).min() else { return }
        currentIndex = first
        model.pageDidChange(first)
    }
}

struct PageCurlView: UIViewControllerRepresentable {
    let model: ReaderModel
    let config: ReaderConfig

    func makeUIViewController(context: Context) -> PageCurlController {
        let controller = PageCurlController(model: model)
        model.controller = controller
        return controller
    }

    func updateUIViewController(_ controller: PageCurlController, context: Context) {
        controller.apply(config: config)
    }
}
