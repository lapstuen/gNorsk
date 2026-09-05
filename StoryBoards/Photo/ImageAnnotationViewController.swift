import UIKit

private func resolveFont(name: String, size: CGFloat) -> UIFont {
    switch name {
    case "bold":   return UIFont.boldSystemFont(ofSize: size)
    case "system": return UIFont.systemFont(ofSize: size)
    default:       return UIFont(name: name, size: size) ?? UIFont.boldSystemFont(ofSize: size)
    }
}

// MARK: - Annotation Tool

enum AnnotationTool {
    case arrow, circle, freehand, rectangle, filledCircle, filledRect, number, text
}

// MARK: - Annotation Item

struct AnnotationItem {
    var tool: AnnotationTool
    var color: UIColor
    var lineWidth: CGFloat
    var points: [CGPoint]
    var number: Int = 0
    var text: String = ""
    var fontSize: CGFloat = 32
    var fontName: String = "bold"
}

// MARK: - Canvas View

class AnnotationCanvasView: UIView {

    var items: [AnnotationItem] = []
    var currentTool: AnnotationTool = .arrow
    var currentColor: UIColor = .systemRed
    var currentLineWidth: CGFloat = 14.0
    var onTextTap: ((CGPoint) -> Void)?
    var onSelectionChanged: ((Int?) -> Void)?
    var onEditTextItem: ((Int) -> Void)?

    private(set) var selectedItemIndex: Int? = nil {
        didSet { onSelectionChanged?(selectedItemIndex) }
    }

    private var currentPoints: [CGPoint] = []
    private var draggedItemIndex: Int? = nil
    private var dragOffset: CGPoint = .zero
    private var touchStartPoint: CGPoint = .zero
    private var didDragSignificantly = false

    func deselect() {
        selectedItemIndex = nil
        setNeedsDisplay()
    }

    func adjustSelectedFontSize(delta: CGFloat) {
        guard let idx = selectedItemIndex, items[idx].tool == .text else { return }
        items[idx].fontSize = max(8, min(1000, items[idx].fontSize + delta))
        setNeedsDisplay()
    }

    private func hitTestTextItem(at point: CGPoint) -> Int? {
        for (index, item) in items.enumerated().reversed() {
            guard item.tool == .text, let pos = item.points.first else { continue }
            let attrs: [NSAttributedString.Key: Any] = [.font: resolveFont(name: item.fontName, size: item.fontSize)]
            let textSize = (item.text as NSString).size(withAttributes: attrs)
            let hitRect = CGRect(x: pos.x - 10, y: pos.y - 10,
                                 width: textSize.width + 20, height: textSize.height + 20)
            if hitRect.contains(point) { return index }
        }
        return nil
    }

    private func hitTestShapeItem(at point: CGPoint) -> Int? {
        for (index, item) in items.enumerated().reversed() {
            guard item.tool == currentTool, item.tool != .text else { continue }
            if item.tool == .freehand {
                guard item.points.count > 1 else { continue }
                let xs = item.points.map { $0.x }
                let ys = item.points.map { $0.y }
                let r = CGRect(x: xs.min()!, y: ys.min()!,
                               width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
                    .insetBy(dx: -20, dy: -20)
                if r.contains(point) { return index }
            } else if item.points.count >= 2 {
                if rectFromPoints(item.points[0], item.points[1])
                    .insetBy(dx: -20, dy: -20).contains(point) { return index }
            }
        }
        return nil
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isOpaque = false
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        for (idx, item) in items.enumerated() {
            renderItem(item, in: ctx)
            if idx == selectedItemIndex, item.tool == .text, let pos = item.points.first {
                let attrs: [NSAttributedString.Key: Any] = [.font: resolveFont(name: item.fontName, size: item.fontSize)]
                let ts = (item.text as NSString).size(withAttributes: attrs)
                let selRect = CGRect(x: pos.x - 6, y: pos.y - 4,
                                     width: ts.width + 12, height: ts.height + 8)
                ctx.setStrokeColor(UIColor.systemYellow.cgColor)
                ctx.setLineWidth(2)
                ctx.setLineDash(phase: 0, lengths: [6, 3])
                ctx.stroke(selRect)
                ctx.setLineDash(phase: 0, lengths: [])
            }
        }
        if !currentPoints.isEmpty {
            let nextNum = items.filter { $0.tool == .number }.count + 1
            let preview = AnnotationItem(tool: currentTool, color: currentColor,
                                         lineWidth: currentLineWidth, points: currentPoints,
                                         number: nextNum)
            renderItem(preview, in: ctx)
        }
    }

    private func renderItem(_ item: AnnotationItem, in ctx: CGContext) {
        ctx.setStrokeColor(item.color.cgColor)
        ctx.setLineWidth(item.lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        switch item.tool {
        case .freehand:
            guard item.points.count > 1 else { return }
            ctx.move(to: item.points[0])
            for pt in item.points.dropFirst() { ctx.addLine(to: pt) }
            ctx.strokePath()

        case .circle:
            guard item.points.count == 2 else { return }
            ctx.strokeEllipse(in: rectFromPoints(item.points[0], item.points[1]))

        case .arrow:
            guard item.points.count == 2 else { return }
            renderArrow(from: item.points[0], to: item.points[1],
                        color: item.color, lineWidth: item.lineWidth, in: ctx)

        case .rectangle:
            guard item.points.count == 2 else { return }
            ctx.stroke(rectFromPoints(item.points[0], item.points[1]))

        case .filledCircle:
            guard item.points.count == 2 else { return }
            ctx.setFillColor(item.color.withAlphaComponent(0.5).cgColor)
            ctx.fillEllipse(in: rectFromPoints(item.points[0], item.points[1]))

        case .filledRect:
            guard item.points.count == 2 else { return }
            ctx.setFillColor(item.color.withAlphaComponent(0.4).cgColor)
            ctx.fill(rectFromPoints(item.points[0], item.points[1]))

        case .number:
            guard item.points.count == 2 else { return }
            let r = rectFromPoints(item.points[0], item.points[1])
            ctx.setFillColor(item.color.cgColor)
            ctx.fillEllipse(in: r)
            let side = min(r.width, r.height)
            let fontSize = max(side * 0.55, 10)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: fontSize),
                .foregroundColor: UIColor.black
            ]
            let str = "\(item.number)" as NSString
            let textSize = str.size(withAttributes: attrs)
            str.draw(in: CGRect(
                x: r.midX - textSize.width / 2,
                y: r.midY - textSize.height / 2,
                width: textSize.width,
                height: textSize.height), withAttributes: attrs)

        case .text:
            guard !item.text.isEmpty, let pt = item.points.first else { return }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: resolveFont(name: item.fontName, size: item.fontSize),
                .foregroundColor: item.color
            ]
            (item.text as NSString).draw(at: pt, withAttributes: attrs)
        }
    }

    private func rectFromPoints(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    private func renderArrow(from start: CGPoint, to end: CGPoint,
                              color: UIColor, lineWidth: CGFloat, in ctx: CGContext) {
        ctx.move(to: start)
        ctx.addLine(to: end)
        ctx.strokePath()
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLen = max(18, lineWidth * 5)
        let headAngle: CGFloat = .pi / 6
        ctx.move(to: end)
        ctx.addLine(to: CGPoint(x: end.x - headLen * cos(angle - headAngle),
                                 y: end.y - headLen * sin(angle - headAngle)))
        ctx.strokePath()
        ctx.move(to: end)
        ctx.addLine(to: CGPoint(x: end.x - headLen * cos(angle + headAngle),
                                 y: end.y - headLen * sin(angle + headAngle)))
        ctx.strokePath()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let pt = touch.location(in: self)
        touchStartPoint = pt
        didDragSignificantly = false

        let hitIdx = currentTool == .text ? hitTestTextItem(at: pt) : hitTestShapeItem(at: pt)
        if let idx = hitIdx {
            draggedItemIndex = idx
            selectedItemIndex = idx
            dragOffset = CGPoint(x: pt.x - items[idx].points[0].x,
                                 y: pt.y - items[idx].points[0].y)
            setNeedsDisplay()
            return
        }
        // Tapped empty space — deselect
        if selectedItemIndex != nil {
            selectedItemIndex = nil
            setNeedsDisplay()
        }
        draggedItemIndex = nil
        currentPoints = [pt]
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let pt = touches.first?.location(in: self) else { return }
        let dist = hypot(pt.x - touchStartPoint.x, pt.y - touchStartPoint.y)
        if dist > 4 { didDragSignificantly = true }

        if let idx = draggedItemIndex {
            let newP0 = CGPoint(x: pt.x - dragOffset.x, y: pt.y - dragOffset.y)
            let delta = CGPoint(x: newP0.x - items[idx].points[0].x,
                                y: newP0.y - items[idx].points[0].y)
            items[idx].points = items[idx].points.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) }
            setNeedsDisplay()
            return
        }
        switch currentTool {
        case .freehand:
            currentPoints.append(pt)
        case .arrow, .circle, .rectangle, .filledCircle, .filledRect, .number:
            currentPoints = currentPoints.isEmpty ? [pt, pt] : [currentPoints[0], pt]
        case .text:
            break
        }
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let pt = touch.location(in: self)

        if let idx = draggedItemIndex {
            let newP0 = CGPoint(x: pt.x - dragOffset.x, y: pt.y - dragOffset.y)
            let delta = CGPoint(x: newP0.x - items[idx].points[0].x,
                                y: newP0.y - items[idx].points[0].y)
            items[idx].points = items[idx].points.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) }
            draggedItemIndex = nil
            dragOffset = .zero
            // Double-tap on text item → open edit dialog
            if !didDragSignificantly && touch.tapCount >= 2 && items[idx].tool == .text {
                onEditTextItem?(idx)
            }
            setNeedsDisplay()
            return
        }

        if currentTool == .text {
            currentPoints = []
            onTextTap?(pt)
            return
        }
        switch currentTool {
        case .freehand:
            currentPoints.append(pt)
        case .arrow, .circle, .rectangle, .filledCircle, .filledRect, .number, .text:
            currentPoints = currentPoints.isEmpty ? [pt, pt] : [currentPoints[0], pt]
        }
        if currentPoints.count >= 2 {
            let nextNum = items.filter { $0.tool == .number }.count + 1
            items.append(AnnotationItem(tool: currentTool, color: currentColor,
                                        lineWidth: currentLineWidth, points: currentPoints,
                                        number: nextNum))
        }
        currentPoints = []
        setNeedsDisplay()
    }

    func undo() {
        if !items.isEmpty {
            if selectedItemIndex == items.count - 1 { selectedItemIndex = nil }
            items.removeLast()
            setNeedsDisplay()
        }
    }
    func clear() { items.removeAll(); selectedItemIndex = nil; setNeedsDisplay() }
}

// MARK: - ImageAnnotationViewController

class ImageAnnotationViewController: UIViewController {

    var sourceImage: UIImage!
    var onSave: ((UIImage) -> Void)?

    private let imageView     = UIImageView()
    private let canvasView    = AnnotationCanvasView()
    private var activeToolBtn  = UIButton()
    private var colorDotBtn   = UIButton()
    private var fontDecBtn    = UIButton()
    private var fontIncBtn    = UIButton()
    private var canDismiss    = false
    private var lastTextValues: (text: String, fontSize: CGFloat, fontName: String) = ("", 32, "bold")

    private let colorPalette: [(String, UIColor)] = [
        ("🔴  Rød",     .systemRed),
        ("🟠  Oransje", .systemOrange),
        ("🟡  Gul",     .systemYellow),
        ("🟢  Grønn",   .systemGreen),
        ("🔵  Blå",     .systemBlue),
        ("⚪  Hvit",    .white),
        ("⚫  Sort",    .black)
    ]

    override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand(input: UIKeyCommand.inputEscape,
                      modifierFlags: [],
                      action: #selector(cancelTapped),
                      discoverabilityTitle: "Avbryt")]
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        buildLayout()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        canDismiss = true
        checkImageResolution()
    }

    private func checkImageResolution() {
        guard let img = sourceImage else { return }
        let w = Int(img.size.width), h = Int(img.size.height)
        guard min(w, h) < 600 else { return }
        let a = UIAlertController(
            title: "⚠️ Lav oppløsning",
            message: "Bildet er \(w)×\(h) px. Annotasjoner kan bli uskarpe etter lagring.",
            preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default))
        present(a, animated: true)
    }

    private func buildLayout() {
        let titleH: CGFloat   = 44
        let toolbarH: CGFloat = 66
        let actionH: CGFloat  = 50

        let titleBar = UIView()
        titleBar.backgroundColor = UIColor(white: 0.1, alpha: 1)
        titleBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleBar)

        let titleLabel = UILabel()
        titleLabel.text = "✍️  Rediger bilde"
        titleLabel.textColor = .white
        titleLabel.font = .boldSystemFont(ofSize: 17)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleBar.addSubview(titleLabel)

        let blankBtn = UIButton(type: .system)
        blankBtn.setTitle("Blankt", for: .normal)
        blankBtn.setTitleColor(UIColor.white.withAlphaComponent(0.7), for: .normal)
        blankBtn.titleLabel?.font = .systemFont(ofSize: 14)
        blankBtn.addTarget(self, action: #selector(blankCanvasTapped), for: .touchUpInside)
        blankBtn.translatesAutoresizingMaskIntoConstraints = false
        titleBar.addSubview(blankBtn)

        NSLayoutConstraint.activate([
            titleBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            titleBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            titleBar.topAnchor.constraint(equalTo: view.topAnchor),
            titleBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: titleH),
            titleLabel.centerXAnchor.constraint(equalTo: titleBar.centerXAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: titleBar.bottomAnchor, constant: -10),
            blankBtn.trailingAnchor.constraint(equalTo: titleBar.trailingAnchor, constant: -16),
            blankBtn.bottomAnchor.constraint(equalTo: titleBar.bottomAnchor, constant: -10),
        ])

        let actionBar = UIView()
        actionBar.backgroundColor = UIColor(white: 0.07, alpha: 1)
        actionBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(actionBar)

        let cancelBtn = makeTextButton(title: "Avbryt", color: .white, action: #selector(cancelTapped))
        let saveBtn   = makeTextButton(title: "  Lagre  ", color: .black, action: #selector(saveTapped))
        saveBtn.backgroundColor = .systemYellow
        saveBtn.layer.cornerRadius = 8
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        saveBtn.translatesAutoresizingMaskIntoConstraints = false
        actionBar.addSubview(cancelBtn)
        actionBar.addSubview(saveBtn)

        NSLayoutConstraint.activate([
            actionBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            actionBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            actionBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            actionBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -actionH),
            cancelBtn.leadingAnchor.constraint(equalTo: actionBar.leadingAnchor, constant: 24),
            cancelBtn.centerYAnchor.constraint(equalTo: actionBar.topAnchor, constant: actionH / 2),
            saveBtn.trailingAnchor.constraint(equalTo: actionBar.trailingAnchor, constant: -24),
            saveBtn.centerYAnchor.constraint(equalTo: actionBar.topAnchor, constant: actionH / 2),
            saveBtn.heightAnchor.constraint(equalToConstant: 36)
        ])

        let toolbar = UIView()
        toolbar.backgroundColor = UIColor(white: 0.13, alpha: 1)
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toolbar)

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: actionBar.topAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: toolbarH)
        ])

        let toolStack = UIStackView()
        toolStack.axis = .horizontal
        toolStack.spacing = 8
        toolStack.alignment = .center
        toolStack.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(toolStack)

        NSLayoutConstraint.activate([
            toolStack.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 12),
            toolStack.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -12),
            toolStack.topAnchor.constraint(equalTo: toolbar.topAnchor),
            toolStack.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor)
        ])

        activeToolBtn = makeIconBtn(symbol: "arrow.up.right", color: .systemYellow, tag: 100)
        activeToolBtn.addTarget(self, action: #selector(activeToolTapped), for: .touchUpInside)
        var activeBg = UIBackgroundConfiguration.clear()
        activeBg.backgroundColor = UIColor.white.withAlphaComponent(0.18)
        activeBg.cornerRadius = 10
        activeToolBtn.configuration?.background = activeBg
        toolStack.addArrangedSubview(activeToolBtn)

        toolStack.addArrangedSubview(makeSep())

        colorDotBtn = makeIconBtn(symbol: "circle.fill", color: canvasView.currentColor, tag: 300)
        colorDotBtn.addTarget(self, action: #selector(colorPickerTapped), for: .touchUpInside)
        toolStack.addArrangedSubview(colorDotBtn)

        toolStack.addArrangedSubview(makeSep())

        let undoBtn = makeIconBtn(symbol: "arrow.uturn.backward", color: .white, tag: 200)
        undoBtn.addTarget(self, action: #selector(undoTapped), for: .touchUpInside)
        toolStack.addArrangedSubview(undoBtn)

        let clearBtn = makeIconBtn(symbol: "trash", color: .systemRed, tag: 201)
        clearBtn.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)
        toolStack.addArrangedSubview(clearBtn)

        toolStack.addArrangedSubview(makeSep())

        fontDecBtn = makeIconBtn(symbol: "textformat.size.smaller", color: .systemYellow, tag: 400)
        fontDecBtn.addTarget(self, action: #selector(fontDecTapped), for: .touchUpInside)
        fontDecBtn.isHidden = true
        toolStack.addArrangedSubview(fontDecBtn)

        fontIncBtn = makeIconBtn(symbol: "textformat.size.larger", color: .systemYellow, tag: 401)
        fontIncBtn.addTarget(self, action: #selector(fontIncTapped), for: .touchUpInside)
        fontIncBtn.isHidden = true
        toolStack.addArrangedSubview(fontIncBtn)

        imageView.image = sourceImage
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .black
        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: titleBar.bottomAnchor),
            imageView.bottomAnchor.constraint(equalTo: toolbar.topAnchor)
        ])

        canvasView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(canvasView)

        NSLayoutConstraint.activate([
            canvasView.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            canvasView.topAnchor.constraint(equalTo: imageView.topAnchor),
            canvasView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor)
        ])

        canvasView.onTextTap = { [weak self] point in
            self?.showTextInputVC(at: point)
        }

        canvasView.onSelectionChanged = { [weak self] idx in
            guard let self else { return }
            let hasTextSelected = idx.map { self.canvasView.items[$0].tool == .text } ?? false
            self.fontDecBtn.isHidden = !hasTextSelected
            self.fontIncBtn.isHidden = !hasTextSelected
        }

        canvasView.onEditTextItem = { [weak self] idx in
            self?.showTextEditVC(for: idx)
        }

        selectTool(at: 0)
    }

    private func makeIconBtn(symbol: String, color: UIColor, tag: Int) -> UIButton {
        var cfg = UIButton.Configuration.plain()
        cfg.image = UIImage(systemName: symbol,
                            withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .medium))?
            .withTintColor(color, renderingMode: .alwaysOriginal)
        let btn = UIButton(configuration: cfg)
        btn.tag = tag
        btn.widthAnchor.constraint(equalToConstant: 52).isActive = true
        return btn
    }

    private func makeTextButton(title: String, color: UIColor, action: Selector) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.setTitleColor(color, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 17)
        btn.addTarget(self, action: action, for: .touchUpInside)
        return btn
    }

    private func makeSep() -> UIView {
        let v = UIView()
        v.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        v.heightAnchor.constraint(equalToConstant: 32).isActive = true
        return v
    }

    private let toolMap: [AnnotationTool] = [.arrow, .circle, .freehand, .rectangle, .filledCircle, .filledRect, .number, .text]

    private let availableFonts: [(display: String, name: String)] = [
        ("System Fet",          "bold"),
        ("System Normal",       "system"),
        ("Georgia",             "Georgia"),
        ("Georgia Fet",         "Georgia-Bold"),
        ("Times New Roman",     "TimesNewRomanPSMT"),
        ("Courier",             "Courier"),
        ("Courier Fet",         "Courier-Bold"),
        ("American Typewriter", "AmericanTypewriter"),
        ("Palatino",            "Palatino-Roman"),
        ("Palatino Fet",        "Palatino-Bold"),
        ("Noteworthy",          "Noteworthy-Light"),
        ("Marker Felt",         "MarkerFelt-Thin"),
    ]

    private func showTextInputVC(at point: CGPoint) {
        let saved = lastTextValues
        let vc = TextAnnotationInputVC(
            fonts: availableFonts,
            initialText: saved.text,
            initialFontName: saved.fontName,
            initialFontSize: saved.fontSize
        ) { [weak self] text, fontName, fontSize in
            guard let self else { return }
            self.lastTextValues = (text, fontSize, fontName)
            var item = AnnotationItem(
                tool: .text,
                color: self.canvasView.currentColor,
                lineWidth: self.canvasView.currentLineWidth,
                points: [point])
            item.text     = text
            item.fontSize = fontSize
            item.fontName = fontName
            self.canvasView.items.append(item)
            self.canvasView.setNeedsDisplay()
        }
        vc.modalPresentationStyle = .formSheet
        vc.preferredContentSize = CGSize(width: 380, height: 520)
        present(vc, animated: true)
    }

    private func selectTool(at index: Int) {
        let symbols = ["arrow.up.right","circle","pencil","rectangle",
                       "circle.fill","rectangle.fill","number.circle.fill","textformat"]
        activeToolBtn.configuration?.image = UIImage(
            systemName: symbols[index],
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .medium))?
            .withTintColor(.systemYellow, renderingMode: .alwaysOriginal)
        canvasView.currentTool = toolMap[index]
    }

    @objc private func activeToolTapped() {
        let toolDefs: [(String, String)] = [
            ("arrow.up.right",     "Pil"),
            ("circle",             "Sirkel"),
            ("pencil",             "Frihånd"),
            ("rectangle",          "Rektangel"),
            ("circle.fill",        "Fylt sirkel"),
            ("rectangle.fill",     "Fylt rektangel"),
            ("number.circle.fill", "Nummer"),
            ("textformat",         "Tekst")
        ]
        let sheet = UIAlertController(title: "Velg verktøy", message: nil, preferredStyle: .actionSheet)
        for (i, def) in toolDefs.enumerated() {
            let isActive = canvasView.currentTool == toolMap[i]
            sheet.addAction(UIAlertAction(title: isActive ? "✓  \(def.1)" : def.1, style: .default) { [weak self] _ in
                self?.selectTool(at: i)
            })
        }
        sheet.addAction(UIAlertAction(title: "Avbryt", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = activeToolBtn
            pop.sourceRect = activeToolBtn.bounds
        }
        present(sheet, animated: true)
    }

    @objc private func colorPickerTapped() {
        let alert = UIAlertController(title: "Velg farge", message: nil, preferredStyle: .alert)
        for (name, color) in colorPalette {
            alert.addAction(UIAlertAction(title: name, style: .default) { [weak self] _ in
                guard let self else { return }
                self.canvasView.currentColor = color
                self.colorDotBtn.configuration?.image = UIImage(
                    systemName: "circle.fill",
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .medium))?
                    .withTintColor(color, renderingMode: .alwaysOriginal)
            })
        }
        alert.addAction(UIAlertAction(title: "Avbryt", style: .cancel))
        present(alert, animated: true)
    }

    @objc private func undoTapped() {
        guard !canvasView.items.isEmpty else { return }
        let removed = canvasView.items.last
        canvasView.undo()
        if removed?.tool == .text, let pt = removed?.points.first {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.showTextInputVC(at: pt)
            }
        }
    }

    @objc private func clearTapped() {
        guard !canvasView.items.isEmpty else { return }
        let a = UIAlertController(title: "Tøm alle tegninger?", message: nil, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Tøm", style: .destructive) { [weak self] _ in self?.canvasView.clear() })
        a.addAction(UIAlertAction(title: "Avbryt", style: .cancel))
        present(a, animated: true)
    }

    @objc private func fontDecTapped() { canvasView.adjustSelectedFontSize(delta: -4) }
    @objc private func fontIncTapped() { canvasView.adjustSelectedFontSize(delta: +4) }

    private func showTextEditVC(for index: Int) {
        guard index < canvasView.items.count else { return }
        let item = canvasView.items[index]
        let vc = TextAnnotationInputVC(
            fonts: availableFonts,
            initialText: item.text,
            initialFontName: item.fontName,
            initialFontSize: item.fontSize,
            onDelete: { [weak self] in
                guard let self, index < self.canvasView.items.count else { return }
                self.canvasView.items.remove(at: index)
                self.canvasView.deselect()
            },
            onConfirm: { [weak self] text, fontName, fontSize in
                guard let self, index < self.canvasView.items.count else { return }
                self.canvasView.items[index].text     = text
                self.canvasView.items[index].fontName = fontName
                self.canvasView.items[index].fontSize = fontSize
                self.lastTextValues = (text, fontSize, fontName)
                self.canvasView.setNeedsDisplay()
            }
        )
        vc.modalPresentationStyle = .formSheet
        vc.preferredContentSize = CGSize(width: 380, height: 580)
        present(vc, animated: true)
    }

    @objc private func cancelTapped() {
        guard canDismiss else { return }
        dismiss(animated: true)
    }

    @objc private func blankCanvasTapped() {
        let a = UIAlertController(title: "Blankt lerret",
                                   message: "Erstatter bildet med et hvitt 1024×1024 lerret og sletter alle tegninger.",
                                   preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Lag blankt", style: .destructive) { [weak self] _ in
            guard let self else { return }
            let size = CGSize(width: 1024, height: 1024)
            let fmt = UIGraphicsImageRendererFormat()
            fmt.scale = 1.0
            let blank = UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
            }
            self.sourceImage = blank
            self.imageView.image = blank
            self.canvasView.clear()
        })
        a.addAction(UIAlertAction(title: "Avbryt", style: .cancel))
        present(a, animated: true)
    }

    @objc private func saveTapped() {
        guard !canvasView.items.isEmpty else {
            let a = UIAlertController(title: "Ingen tegninger",
                                       message: "Tegn noe på bildet før du lagrer.", preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "OK", style: .default))
            present(a, animated: true)
            return
        }
        let img = renderAnnotatedImage()
        dismiss(animated: true) { [weak self] in self?.onSave?(img) }
    }

    private func renderAnnotatedImage() -> UIImage {
        guard let source = sourceImage else { return UIImage() }
        let imageSize = source.size
        let canvasSize = canvasView.bounds.size
        guard canvasSize.width > 0, canvasSize.height > 0 else { return source }

        let fit = aspectFitRect(imageSize: imageSize, in: canvasSize)
        let sx = imageSize.width  / fit.width
        let sy = imageSize.height / fit.height

        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1.0
        return UIGraphicsImageRenderer(size: imageSize, format: fmt).image { ctx in
            source.draw(in: CGRect(origin: .zero, size: imageSize))
            let c = ctx.cgContext
            c.setLineCap(.round); c.setLineJoin(.round)

            for item in canvasView.items {
                let pts = item.points.map {
                    CGPoint(x: ($0.x - fit.origin.x) * sx, y: ($0.y - fit.origin.y) * sy)
                }
                guard pts.count >= 2 || item.tool == .text else { continue }
                let lw = max(item.lineWidth * sx, imageSize.width / 80.0)

                switch item.tool {
                case .freehand:
                    c.setLineWidth(lw); c.setStrokeColor(item.color.cgColor)
                    c.move(to: pts[0]); pts.dropFirst().forEach { c.addLine(to: $0) }; c.strokePath()

                case .circle:
                    c.setLineWidth(lw); c.setStrokeColor(item.color.cgColor)
                    c.strokeEllipse(in: exportRect(pts))

                case .arrow:
                    c.setLineWidth(lw); c.setStrokeColor(item.color.cgColor)
                    let (s, e) = (pts[0], pts[1])
                    c.move(to: s); c.addLine(to: e); c.strokePath()
                    let ang = atan2(e.y - s.y, e.x - s.x)
                    let hl = max(20, lw * 5), ha: CGFloat = .pi / 6
                    c.move(to: e); c.addLine(to: CGPoint(x: e.x - hl*cos(ang-ha), y: e.y - hl*sin(ang-ha))); c.strokePath()
                    c.move(to: e); c.addLine(to: CGPoint(x: e.x - hl*cos(ang+ha), y: e.y - hl*sin(ang+ha))); c.strokePath()

                case .rectangle:
                    c.setLineWidth(lw); c.setStrokeColor(item.color.cgColor)
                    c.stroke(exportRect(pts))

                case .filledCircle:
                    c.setFillColor(item.color.withAlphaComponent(0.5).cgColor)
                    c.fillEllipse(in: exportRect(pts))

                case .filledRect:
                    c.setFillColor(item.color.withAlphaComponent(0.4).cgColor)
                    c.fill(exportRect(pts))

                case .number:
                    let r = exportRect(pts)
                    c.setFillColor(item.color.cgColor); c.fillEllipse(in: r)
                    let side = min(r.width, r.height)
                    let fontSize = max(side * 0.55, 20)
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.boldSystemFont(ofSize: fontSize), .foregroundColor: UIColor.black
                    ]
                    let str = "\(item.number)" as NSString
                    let ts = str.size(withAttributes: attrs)
                    str.draw(in: CGRect(x: r.midX - ts.width/2, y: r.midY - ts.height/2,
                                        width: ts.width, height: ts.height), withAttributes: attrs)

                case .text:
                    guard !item.text.isEmpty else { continue }
                    let imagePt = CGPoint(
                        x: (item.points[0].x - fit.origin.x) * sx,
                        y: (item.points[0].y - fit.origin.y) * sy)
                    let scaledSize = max(item.fontSize * sx, 8)
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: resolveFont(name: item.fontName, size: scaledSize),
                        .foregroundColor: item.color
                    ]
                    (item.text as NSString).draw(at: imagePt, withAttributes: attrs)
                }
            }
        }
    }

    private func exportRect(_ pts: [CGPoint]) -> CGRect {
        CGRect(x: min(pts[0].x, pts[1].x), y: min(pts[0].y, pts[1].y),
               width: abs(pts[1].x - pts[0].x), height: abs(pts[1].y - pts[0].y))
    }

    private func aspectFitRect(imageSize: CGSize, in viewSize: CGSize) -> CGRect {
        let ia = imageSize.width / imageSize.height
        let va = viewSize.width  / viewSize.height
        var r = CGRect.zero
        if ia > va {
            r.size.width  = viewSize.width
            r.size.height = viewSize.width / ia
            r.origin.y    = (viewSize.height - r.size.height) / 2
        } else {
            r.size.height = viewSize.height
            r.size.width  = viewSize.height * ia
            r.origin.x    = (viewSize.width - r.size.width) / 2
        }
        return r
    }
}

// MARK: - TextAnnotationInputVC

private class TextAnnotationInputVC: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private let fonts: [(display: String, name: String)]
    private let onConfirm: (String, String, CGFloat) -> Void
    private let onDelete: (() -> Void)?

    private let textField    = UITextField()
    private let tableView    = UITableView(frame: .zero, style: .plain)
    private let slider       = UISlider()
    private let sizeLabel    = UILabel()
    private var selectedRow  = 0
    private var currentSize: CGFloat

    init(fonts: [(display: String, name: String)],
         initialText: String,
         initialFontName: String,
         initialFontSize: CGFloat,
         onDelete: (() -> Void)? = nil,
         onConfirm: @escaping (String, String, CGFloat) -> Void) {
        self.fonts = fonts
        self.onConfirm = onConfirm
        self.onDelete = onDelete
        self.currentSize = initialFontSize
        super.init(nibName: nil, bundle: nil)
        self.selectedRow = fonts.firstIndex(where: { $0.name == initialFontName }) ?? 0
        textField.text = initialText
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        buildLayout()
        tableView.selectRow(at: IndexPath(row: selectedRow, section: 0), animated: false, scrollPosition: .middle)
    }

    private func buildLayout() {
        // Title
        let titleLabel = UILabel()
        titleLabel.text = "Legg til tekst"
        titleLabel.font = .boldSystemFont(ofSize: 17)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // Text field
        textField.placeholder = "Skriv tekst her..."
        textField.borderStyle = .roundedRect
        textField.autocapitalizationType = .sentences
        textField.font = .systemFont(ofSize: 16)
        textField.translatesAutoresizingMaskIntoConstraints = false

        // Font section label
        let fontLabel = UILabel()
        fontLabel.text = "Font"
        fontLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        fontLabel.textColor = .secondaryLabel
        fontLabel.translatesAutoresizingMaskIntoConstraints = false

        // Table for font selection
        tableView.dataSource = self
        tableView.delegate   = self
        tableView.allowsSelection = true
        tableView.layer.cornerRadius = 10
        tableView.clipsToBounds = true
        tableView.translatesAutoresizingMaskIntoConstraints = false

        // Size section label + value label
        let sizeSectionLabel = UILabel()
        sizeSectionLabel.text = "Størrelse"
        sizeSectionLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        sizeSectionLabel.textColor = .secondaryLabel
        sizeSectionLabel.translatesAutoresizingMaskIntoConstraints = false

        sizeLabel.text = "\(Int(currentSize))"
        sizeLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .medium)
        sizeLabel.textAlignment = .right
        sizeLabel.setContentHuggingPriority(.required, for: .horizontal)
        sizeLabel.translatesAutoresizingMaskIntoConstraints = false

        let sizeHeaderStack = UIStackView(arrangedSubviews: [sizeSectionLabel, sizeLabel])
        sizeHeaderStack.axis = .horizontal
        sizeHeaderStack.distribution = .fill
        sizeHeaderStack.translatesAutoresizingMaskIntoConstraints = false

        // Slider
        slider.minimumValue = 8
        slider.maximumValue = 1000
        slider.value = Float(currentSize)
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        slider.translatesAutoresizingMaskIntoConstraints = false

        // Buttons
        let cancelBtn = UIButton(type: .system)
        cancelBtn.setTitle("Avbryt", for: .normal)
        cancelBtn.titleLabel?.font = .systemFont(ofSize: 17)
        cancelBtn.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        let addBtn = UIButton(type: .system)
        addBtn.setTitle("Lagre", for: .normal)
        addBtn.titleLabel?.font = .boldSystemFont(ofSize: 17)
        addBtn.backgroundColor = .systemBlue
        addBtn.setTitleColor(.white, for: .normal)
        addBtn.layer.cornerRadius = 10
        addBtn.addTarget(self, action: #selector(addTapped), for: .touchUpInside)

        let btnStack = UIStackView(arrangedSubviews: [cancelBtn, addBtn])
        btnStack.axis = .horizontal
        btnStack.spacing = 12
        btnStack.distribution = .fillEqually
        btnStack.translatesAutoresizingMaskIntoConstraints = false

        var subviews: [UIView] = [titleLabel, textField, fontLabel, tableView,
                                   sizeHeaderStack, slider, btnStack]

        let deleteBtn: UIButton?
        if onDelete != nil {
            let btn = UIButton(type: .system)
            btn.setTitle("Slett tekst", for: .normal)
            btn.setTitleColor(.systemRed, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 17)
            btn.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
            btn.translatesAutoresizingMaskIntoConstraints = false
            deleteBtn = btn
            subviews.append(btn)
        } else {
            deleteBtn = nil
        }

        subviews.forEach { view.addSubview($0) }

        let m: CGFloat = 20

        var constraints: [NSLayoutConstraint] = [
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -m),

            textField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            textField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),
            textField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -m),
            textField.heightAnchor.constraint(equalToConstant: 40),

            fontLabel.topAnchor.constraint(equalTo: textField.bottomAnchor, constant: 16),
            fontLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),
            fontLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -m),

            tableView.topAnchor.constraint(equalTo: fontLabel.bottomAnchor, constant: 6),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -m),
            tableView.heightAnchor.constraint(equalToConstant: 180),

            sizeHeaderStack.topAnchor.constraint(equalTo: tableView.bottomAnchor, constant: 16),
            sizeHeaderStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),
            sizeHeaderStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -m),

            slider.topAnchor.constraint(equalTo: sizeHeaderStack.bottomAnchor, constant: 6),
            slider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),
            slider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -m),

            btnStack.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: 24),
            btnStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),
            btnStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -m),
            btnStack.heightAnchor.constraint(equalToConstant: 44),
        ]

        if let deleteBtn {
            constraints += [
                deleteBtn.topAnchor.constraint(equalTo: btnStack.bottomAnchor, constant: 12),
                deleteBtn.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                deleteBtn.heightAnchor.constraint(equalToConstant: 44),
            ]
        }

        NSLayoutConstraint.activate(constraints)
    }

    @objc private func sliderChanged() {
        currentSize = CGFloat(slider.value)
        sizeLabel.text = "\(Int(currentSize))"
    }

    @objc private func cancelTapped() { dismiss(animated: true) }

    @objc private func deleteTapped() {
        dismiss(animated: true) { [weak self] in self?.onDelete?() }
    }

    @objc private func addTapped() {
        let raw = textField.text?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !raw.isEmpty else {
            textField.layer.borderColor = UIColor.systemRed.cgColor
            textField.layer.borderWidth = 1.5
            textField.layer.cornerRadius = 6
            return
        }
        let fontName = fonts[selectedRow].name
        dismiss(animated: true) { [weak self] in
            guard let self else { return }
            self.onConfirm(raw, fontName, self.currentSize)
        }
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { fonts.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "f")
            ?? UITableViewCell(style: .default, reuseIdentifier: "f")
        let f = fonts[indexPath.row]
        cell.textLabel?.text = f.display
        cell.textLabel?.font = resolveFont(name: f.name, size: 16)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        selectedRow = indexPath.row
    }
}
