import UIKit
import PDFKit
import PencilKit

protocol IndexedPage: AnyObject {
    var pageIndex: Int { get }
}

enum SpineSide { case left, right, none }

/// An empty sheet (used to pad the last spread when the page count is odd).
final class BlankPageViewController: UIViewController, IndexedPage {
    let pageIndex: Int
    private let paper: UIColor

    init(index: Int, paper: UIColor) {
        pageIndex = index
        self.paper = paper
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = paper
    }
}

/// One physical page: paper, rendered PDF page, highlight layer, and a PencilKit
/// canvas. The last two layers are the "secret" annotation layer.
final class PageContentViewController: UIViewController, IndexedPage, PKCanvasViewDelegate {
    let pageIndex: Int
    var config: ReaderConfig { didSet { if isViewLoaded { applyConfig() } } }
    var spine: SpineSide

    private unowned let model: ReaderModel
    private let page: PDFPage
    private let geometry: PageGeometry

    private let container = UIView()
    private let imageView = UIImageView()
    private let highlightView = HighlightView()
    private let canvas = PKCanvasView()
    private let spineShade = CAGradientLayer()
    private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
    private lazy var tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))

    private var renderedKey = ""
    private var appliedScale: CGFloat = 0
    private var selectionStart: CGPoint?
    private var selectionRects: [CGRect] = []
    private var selectionText = ""

    init(index: Int, page: PDFPage, model: ReaderModel, config: ReaderConfig, spine: SpineSide) {
        pageIndex = index
        self.page = page
        self.model = model
        self.config = config
        self.spine = spine
        geometry = PageGeometry(page: page)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var paper: UIColor { config.night ? Mocha.baseUI : .white }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = paper

        imageView.contentMode = .scaleToFill
        container.addSubview(imageView)
        container.addSubview(highlightView)

        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .anyInput
        canvas.overrideUserInterfaceStyle = .light // keep ink colours exactly as picked
        canvas.isScrollEnabled = false
        canvas.delegate = self
        container.addSubview(canvas)

        pan.maximumNumberOfTouches = 1
        container.addGestureRecognizer(pan)
        container.addGestureRecognizer(tap)

        view.addSubview(container)
        view.layer.addSublayer(spineShade)
        spineShade.startPoint = CGPoint(x: 0, y: 0.5)
        spineShade.endPoint = CGPoint(x: 1, y: 0.5)

        applyConfig()
        refreshHighlights()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let insets = UIEdgeInsets(
            top: max(view.safeAreaInsets.top, 24) + 36,
            left: 14,
            bottom: max(view.safeAreaInsets.bottom, 12) + 44,
            right: 14
        )
        let avail = view.bounds.inset(by: insets)
        let ds = geometry.displaySize
        guard avail.width > 10, avail.height > 10, ds.width > 0, ds.height > 0 else { return }
        let s = min(avail.width / ds.width, avail.height / ds.height)
        let size = CGSize(width: (ds.width * s).rounded(), height: (ds.height * s).rounded())
        container.frame = CGRect(x: avail.midX - size.width / 2, y: avail.midY - size.height / 2,
                                 width: size.width, height: size.height).integral
        imageView.frame = container.bounds
        highlightView.frame = container.bounds
        canvas.frame = container.bounds

        layoutSpine()
        renderPageIfNeeded()
        applyDrawingScaleIfNeeded()
    }

    private func layoutSpine() {
        let width: CGFloat = 38
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        switch spine {
        case .none:
            spineShade.isHidden = true
        case .left:
            spineShade.isHidden = false
            spineShade.frame = CGRect(x: 0, y: 0, width: width, height: view.bounds.height)
            spineShade.colors = [UIColor.black.withAlphaComponent(0.40).cgColor, UIColor.clear.cgColor]
        case .right:
            spineShade.isHidden = false
            spineShade.frame = CGRect(x: view.bounds.width - width, y: 0, width: width, height: view.bounds.height)
            spineShade.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.40).cgColor]
        }
        CATransaction.commit()
    }

    private func renderPageIfNeeded() {
        let size = container.bounds.size
        guard size.width > 1 else { return }
        let key = "\(Int(size.width))x\(Int(size.height))-\(config.night)"
        guard key != renderedKey else { return }
        renderedKey = key
        let scale = max(view.window?.screen.scale ?? UIScreen.main.scale, 2)
        imageView.image = PageRenderer.image(
            for: page, key: "\(model.item.id.uuidString)-\(pageIndex)",
            size: size, night: config.night, scale: scale
        )
    }

    // MARK: Config

    func applyConfig() {
        view.backgroundColor = paper
        let layerVisible = config.showLayer || config.mode != .read
        highlightView.isHidden = !layerVisible
        canvas.isHidden = !layerVisible
        canvas.isUserInteractionEnabled = config.mode == .draw && layerVisible
        pan.isEnabled = config.mode == .highlight
        tap.isEnabled = config.mode == .highlight
        highlightView.previewColor = config.highlightColor.uiColor

        switch config.penTool {
        case .pen:
            canvas.tool = PKInkingTool(.pen, color: config.penColor.uiColor, width: config.penWidth.pen)
        case .marker:
            canvas.tool = PKInkingTool(.marker, color: config.penColor.uiColor, width: config.penWidth.marker)
        case .eraser:
            canvas.tool = PKEraserTool(.vector)
        }
        if config.mode == .draw { canvas.becomeFirstResponder() } else { canvas.resignFirstResponder() }
        renderPageIfNeeded()
    }

    // MARK: Highlights

    func refreshHighlights() {
        highlightView.items = model.annotations.highlights(onPage: pageIndex).map { h in
            HighlightView.Item(rects: h.rects.map(geometry.unitRect(fromPage:)), color: h.color.uiColor)
        }
    }

    private func pagePoint(_ p: CGPoint) -> CGPoint {
        let w = max(container.bounds.width, 1), h = max(container.bounds.height, 1)
        return geometry.page(fromUnit: CGPoint(x: p.x / w, y: p.y / h))
    }

    private func updateSelection(to end: CGPoint) {
        guard let start = selectionStart, let selection = page.selection(from: start, to: end) else {
            selectionRects = []; selectionText = ""
            highlightView.preview = []
            return
        }
        let lines = selection.selectionsByLine()
        selectionRects = lines.map { $0.bounds(for: page) }.filter { !$0.isEmpty }
        selectionText = selection.string ?? ""
        highlightView.preview = selectionRects.map(geometry.unitRect(fromPage:))
    }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        let location = g.location(in: container)
        switch g.state {
        case .began:
            let t = g.translation(in: container)
            selectionStart = pagePoint(CGPoint(x: location.x - t.x, y: location.y - t.y))
            updateSelection(to: pagePoint(location))
        case .changed:
            updateSelection(to: pagePoint(location))
        case .ended:
            updateSelection(to: pagePoint(location))
            let text = selectionText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !selectionRects.isEmpty, !text.isEmpty {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                model.annotations.add(Highlight(page: pageIndex, rects: selectionRects, text: text, color: config.highlightColor))
            }
            fallthrough
        default:
            selectionStart = nil
            selectionRects = []
            selectionText = ""
            highlightView.preview = []
        }
    }

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        let point = pagePoint(g.location(in: container))
        let hit = model.annotations.highlights(onPage: pageIndex).last { h in
            h.rects.contains { $0.insetBy(dx: -3, dy: -3).contains(point) }
        }
        if let hit {
            UISelectionFeedbackGenerator().selectionChanged()
            model.highlightActionID = hit.id
        }
    }

    // MARK: Drawing

    private var canonicalSize: CGSize { geometry.displaySize }

    private func applyDrawingScaleIfNeeded() {
        guard container.bounds.width > 1 else { return }
        let s = container.bounds.width / canonicalSize.width
        guard abs(s - appliedScale) > 0.0005 else { return }
        appliedScale = s
        if let data = model.annotations.drawingData(page: pageIndex), let d = try? PKDrawing(data: data) {
            canvas.drawing = d.transformed(using: CGAffineTransform(scaleX: s, y: s))
        } else {
            canvas.drawing = PKDrawing()
        }
        canvas.undoManager?.removeAllActions()
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard appliedScale > 0 else { return }
        let normalized = canvasView.drawing.transformed(using: CGAffineTransform(scaleX: 1 / appliedScale, y: 1 / appliedScale))
        model.annotations.setDrawing(normalized.strokes.isEmpty ? nil : normalized.dataRepresentation(), page: pageIndex)
        model.touchHistory()
    }

    var canUndo: Bool { canvas.undoManager?.canUndo ?? false }
    var canRedo: Bool { canvas.undoManager?.canRedo ?? false }
    func undo() { canvas.undoManager?.undo() }
    func redo() { canvas.undoManager?.redo() }
}
