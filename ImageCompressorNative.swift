import AppKit
import UniformTypeIdentifiers
import UserNotifications

// MARK: - Localization

private func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

// MARK: - App Logger

private final class AppLogger {
    static let shared = AppLogger()

    private let logURL: URL = {
        let logDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/ImageCompressor", isDirectory: true)
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dated = logDir.appendingPathComponent("run-\(formatter.string(from: Date())).log")
        if !FileManager.default.fileExists(atPath: dated.path) {
            FileManager.default.createFile(atPath: dated.path, contents: nil)
        }
        return dated
    }()

    func write(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        cleanupOldLogs(keepDays: 30)
        guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }

    private func cleanupOldLogs(keepDays: Int) {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: logURL.deletingLastPathComponent(),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date().addingTimeInterval(TimeInterval(-keepDays * 24 * 60 * 60))
        for url in urls where url.pathExtension == "log" {
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantFuture
            if mtime < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}

// MARK: - Design Tokens

private enum Palette {
    // Window
    static let window = NSColor(calibratedWhite: 0.898, alpha: 1.0)
    static let sidebar = NSColor(calibratedWhite: 0.898, alpha: 1.0)

    // Surfaces
    static let surface = NSColor(calibratedWhite: 0.94, alpha: 0.78)
    static let surfaceElevated = NSColor(calibratedWhite: 0.975, alpha: 0.88)
    static let surfaceTinted = NSColor(calibratedRed: 0.94, green: 0.92, blue: 0.99, alpha: 0.96)
    static let surfaceInset = NSColor(calibratedWhite: 0.82, alpha: 0.78)

    // Borders
    static let border = NSColor.white.withAlphaComponent(0.92)
    static let borderSubtle = NSColor.white.withAlphaComponent(0.72)

    // Text
    static let text = NSColor(calibratedWhite: 0.09, alpha: 1.0)
    static let textSecondary = NSColor(calibratedWhite: 0.28, alpha: 1.0)
    static let textTertiary = NSColor(calibratedWhite: 0.58, alpha: 1.0)
    static let textOnAccent = NSColor.white

    // Accent
    static let accent = NSColor(calibratedRed: 0.267, green: 0.133, blue: 0.631, alpha: 1.0)
    static let accentHover = NSColor(calibratedRed: 0.31, green: 0.17, blue: 0.70, alpha: 1.0)
    static let accentPressed = NSColor(calibratedRed: 0.21, green: 0.09, blue: 0.52, alpha: 1.0)
    static let accentSoft = NSColor(calibratedRed: 0.31, green: 0.14, blue: 0.82, alpha: 0.08)
    static let accentSoftPressed = NSColor(calibratedRed: 0.31, green: 0.14, blue: 0.82, alpha: 0.15)

    // Status
    static let success = NSColor(calibratedRed: 0.08, green: 0.62, blue: 0.38, alpha: 1.0)
    static let successSoft = NSColor(calibratedRed: 0.08, green: 0.62, blue: 0.38, alpha: 0.12)
    static let warning = NSColor(calibratedRed: 0.72, green: 0.45, blue: 0.10, alpha: 1.0)
    static let warningSoft = NSColor(calibratedRed: 0.72, green: 0.45, blue: 0.10, alpha: 0.12)
    static let danger = NSColor(calibratedRed: 0.82, green: 0.20, blue: 0.20, alpha: 1.0)
    static let dangerSoft = NSColor(calibratedRed: 0.82, green: 0.20, blue: 0.20, alpha: 0.10)

    // Special
    static let overlay = NSColor.black.withAlphaComponent(0.64)
    static let focusRing = NSColor(calibratedRed: 0.04, green: 0.42, blue: 0.98, alpha: 0.45)
}

private enum Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
    static let xxxl: CGFloat = 64
}

private enum Radius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 28
}

private enum Typography {
    static let heroTitle = NSFont.systemFont(ofSize: 28, weight: .semibold)
    static let sectionTitle = NSFont.systemFont(ofSize: 18, weight: .semibold)
    static let cardTitle = NSFont.systemFont(ofSize: 15, weight: .semibold)
    static let body = NSFont.systemFont(ofSize: 14, weight: .regular)
    static let bodyMedium = NSFont.systemFont(ofSize: 14, weight: .medium)
    static let caption = NSFont.systemFont(ofSize: 12, weight: .regular)
    static let captionMedium = NSFont.systemFont(ofSize: 12, weight: .medium)
    static let micro = NSFont.systemFont(ofSize: 11, weight: .medium)
    static let monoSmall = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    static let display = NSFont.systemFont(ofSize: 28, weight: .semibold)
}

private enum FigmaLayout {
    static let canvasWidth: CGFloat = 1280
    static let canvasHeight: CGFloat = 832
    static let pageInset: CGFloat = 40
    static let emptyDropWidth: CGFloat = 640
    static let emptyDropHeight: CGFloat = 240
    static let compactDropHeight: CGFloat = 140
    static let queueWidth: CGFloat = 330
    static let inspectorWidth: CGFloat = 350
}

private enum MotionTokens {
    static let quick: TimeInterval = 0.14
    static let standard: TimeInterval = 0.22
    static let emphasized: TimeInterval = 0.32
    static let spring = (damping: 0.82, response: 0.32)
}

// MARK: - Helpers

private func makeLabel(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = font
    label.textColor = color
    label.alignment = .left
    label.lineBreakMode = .byTruncatingTail
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
}

private func makeWrappingLabel(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: text)
    label.font = font
    label.textColor = color
    label.alignment = .left
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
}

private func makeSymbol(_ name: String, size: CGFloat = 14, weight: NSFont.Weight = .regular, color: NSColor) -> NSImageView {
    let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
    let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
    let view = NSImageView(image: image.withSymbolConfiguration(config) ?? image)
    view.contentTintColor = color
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
}

// MARK: - Background

private final class AppBackgroundView: NSView {
    private let gradient = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        gradient.colors = [
            Palette.window.cgColor,
            Palette.window.cgColor,
            Palette.window.cgColor
        ]
        gradient.locations = [0, 0.5, 1]
        gradient.startPoint = CGPoint(x: 0, y: 1)
        gradient.endPoint = CGPoint(x: 1, y: 0)
        layer?.addSublayer(gradient)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        gradient.frame = bounds
    }
}

// MARK: - Flipped View (for scroll documents)

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - Glass Card

private final class GlassCard: NSVisualEffectView {
    let cornerRadius: CGFloat

    init(cornerRadius: CGFloat = Radius.xl, material: NSVisualEffectView.Material = .hudWindow) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        self.material = material
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = min(cornerRadius, Radius.lg)
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        layer?.borderColor = Palette.borderSubtle.cgColor
        layer?.backgroundColor = Palette.surface.cgColor
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.32).cgColor
        layer?.shadowOffset = CGSize(width: 0, height: -1)
        layer?.shadowRadius = 8
        layer?.shadowOpacity = 0.55
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Pill Label

private final class PillLabel: NSView {
    private let stack = NSStackView()
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let dotLayer = CALayer()

    init(text: String, symbol: String? = nil, tint: NSColor = Palette.accent) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = tint.withAlphaComponent(0.12).cgColor

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        if let symbol {
            iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
            iconView.contentTintColor = tint
            iconView.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(iconView)
        }
        label.stringValue = text
        label.font = Typography.captionMedium
        label.textColor = tint
        label.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(label)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func setText(_ text: String) { label.stringValue = text }
}

extension NSStackView {
    var edgeInsets: NSEdgeInsets {
        get {
            (associatedObjects["edgeInsets"] as? NSEdgeInsets) ?? NSEdgeInsets()
        }
        set {
            associatedObjects["edgeInsets"] = newValue
            if let constraint = (constraints.first { $0.firstItem === self && ($0.firstAttribute == .top || $0.firstAttribute == .bottom || $0.firstAttribute == .leading || $0.firstAttribute == .trailing) }) {
                constraint.constant = 0
            }
        }
    }
}

private var associatedObjects: [String: Any] = [:]

// MARK: - Stat Tile

private final class StatTile: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")

    init(title: String, value: String, detail: String = "", valueColor: NSColor = Palette.text) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = Palette.surfaceElevated.cgColor
        layer?.cornerRadius = Radius.xl
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.7
        layer?.borderColor = Palette.border.cgColor

        titleLabel.stringValue = title
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = Palette.textTertiary
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        valueLabel.stringValue = value
        valueLabel.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        valueLabel.textColor = valueColor
        valueLabel.alignment = .center
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        detailLabel.stringValue = detail
        detailLabel.font = Typography.caption
        detailLabel.textColor = Palette.textSecondary
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(titleLabel)
        addSubview(valueLabel)
        detailLabel.isHidden = true

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            valueLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor),
            valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            valueLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
            heightAnchor.constraint(equalToConstant: 52)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func setValue(_ value: String) {
        guard valueLabel.stringValue != value else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            valueLabel.stringValue = value
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = MotionTokens.quick
            valueLabel.animator().alphaValue = 0.35
        } completionHandler: { [weak self] in
            self?.valueLabel.stringValue = value
            NSAnimationContext.runAnimationGroup { context in
                context.duration = MotionTokens.quick
                self?.valueLabel.animator().alphaValue = 1
            }
        }
    }
    func setDetail(_ detail: String) { detailLabel.stringValue = detail }
    func setValueColor(_ color: NSColor) { valueLabel.textColor = color }
}

// MARK: - Primary Button

private final class PrimaryButton: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }
    convenience init(title: String, symbol: String? = nil) {
        self.init(frame: .zero)
        self.title = title
        self.toolTip = title
        if let symbol { configureSymbol(symbol) }
    }
    required init?(coder: NSCoder) { fatalError() }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        bezelStyle = .regularSquare
        isBordered = false
        wantsLayer = true
        focusRingType = .exterior
        layer?.cornerRadius = Radius.md
        layer?.cornerCurve = .continuous
        contentTintColor = Palette.textOnAccent
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: Typography.bodyMedium,
                .foregroundColor: Palette.textOnAccent
            ]
        )
        heightAnchor.constraint(equalToConstant: 44).isActive = true
    }

    private func configureSymbol(_ name: String) {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
        image.isTemplate = true
        self.image = image
        self.imagePosition = .imageLeading
        self.imageScaling = .scaleProportionallyDown
    }

    override func updateLayer() {
        super.updateLayer()
        guard let layer = layer else { return }
        if isHighlighted {
            layer.backgroundColor = Palette.accentPressed.cgColor
        } else {
            layer.backgroundColor = isEnabled ? Palette.accent.cgColor : Palette.textTertiary.withAlphaComponent(0.4).cgColor
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isEnabled ? super.hitTest(point) : nil
    }

    override func mouseDown(with event: NSEvent) {
        layer?.setAffineTransform(CGAffineTransform(scaleX: 0.97, y: 0.97))
        super.mouseDown(with: event)
        layer?.setAffineTransform(.identity)
    }
}

private final class SecondaryButton: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }
    convenience init(title: String, symbol: String? = nil, tint: NSColor = Palette.text) {
        self.init(frame: .zero)
        self.title = title
        self.toolTip = title
        self.tint = tint
        if let symbol { configureSymbol(symbol) }
    }
    required init?(coder: NSCoder) { fatalError() }

    private var tint: NSColor = Palette.text

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        bezelStyle = .regularSquare
        isBordered = false
        wantsLayer = true
        focusRingType = .exterior
        layer?.cornerRadius = Radius.md
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: tint
            ]
        )
        heightAnchor.constraint(equalToConstant: 48).isActive = true
    }

    private func configureSymbol(_ name: String) {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
        image.isTemplate = true
        self.image = image
        self.imagePosition = .imageLeading
        self.imageScaling = .scaleProportionallyDown
    }

    override func updateLayer() {
        super.updateLayer()
        guard let layer = layer else { return }
        if isHighlighted {
            layer.backgroundColor = Palette.surfaceTinted.cgColor
        } else {
            layer.backgroundColor = isEnabled
                ? Palette.surfaceElevated.cgColor
                : Palette.surfaceInset.cgColor
        }
        layer.borderColor = isEnabled
            ? Palette.borderSubtle.cgColor
            : Palette.borderSubtle.withAlphaComponent(0.5).cgColor
        contentTintColor = isEnabled ? tint : Palette.textTertiary
    }

    override func mouseDown(with event: NSEvent) {
        layer?.setAffineTransform(CGAffineTransform(scaleX: 0.97, y: 0.97))
        super.mouseDown(with: event)
        layer?.setAffineTransform(.identity)
    }
}

private final class ModeButton: NSButton {
    private let tint: NSColor = Palette.accent
    private let iconView = NSImageView()
    private let textLabel = NSTextField(labelWithString: "")
    var isActive = false { didSet { needsDisplay = true; needsLayout = true } }

    init(title: String, symbol: String) {
        super.init(frame: .zero)
        self.title = ""
        translatesAutoresizingMaskIntoConstraints = false
        bezelStyle = .regularSquare
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.cornerCurve = .continuous
        focusRingType = .exterior
        setAccessibilityLabel(title)

        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 24).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 24).isActive = true

        textLabel.stringValue = title
        textLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        textLabel.translatesAutoresizingMaskIntoConstraints = false

        let content = NSStackView(views: [iconView, textLabel])
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 8
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.centerXAnchor.constraint(equalTo: centerXAnchor),
            content.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateLayer() {
        super.updateLayer()
        layer?.backgroundColor = (isActive ? Palette.accentSoft : NSColor.clear).cgColor
        let color = isActive ? tint : Palette.textSecondary
        iconView.contentTintColor = color
        textLabel.textColor = color
    }

    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }
}

private final class PaddedActionButton: NSButton {
    private let tint: NSColor
    private let labelText: String
    private let labelFont: NSFont
    private let requestedIconSize: CGFloat

    init(title: String, symbol: String, tint: NSColor, fontSize: CGFloat = 15, iconSize: CGFloat = 24) {
        self.tint = tint
        self.labelText = title
        self.labelFont = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        self.requestedIconSize = iconSize
        super.init(frame: .zero)
        self.title = title
        translatesAutoresizingMaskIntoConstraints = false
        bezelStyle = .regularSquare
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 20
        layer?.cornerCurve = .continuous
        focusRingType = .exterior
        setAccessibilityLabel(title)
        let baseSymbol = NSImage(systemSymbolName: symbol, accessibilityDescription: title) ?? NSImage()
        let configuration = NSImage.SymbolConfiguration(pointSize: min(iconSize, 16), weight: .medium)
        let symbolImage = baseSymbol.withSymbolConfiguration(configuration) ?? baseSymbol
        let spacedImage = NSImage(size: NSSize(width: iconSize + 4, height: iconSize))
        spacedImage.lockFocus()
        symbolImage.draw(in: NSRect(x: 0, y: 0, width: iconSize, height: iconSize))
        spacedImage.unlockFocus()
        spacedImage.isTemplate = true
        image = spacedImage
        imagePosition = .imageLeading
        imageScaling = .scaleProportionallyDown
        imageHugsTitle = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateLayer() {
        super.updateLayer()
        layer?.backgroundColor = (isHighlighted ? Palette.surfaceInset : Palette.surfaceElevated).cgColor
        contentTintColor = tint
        attributedTitle = NSAttributedString(string: labelText, attributes: [
            .font: labelFont,
            .foregroundColor: tint
        ])
    }

    override var intrinsicContentSize: NSSize {
        let textSize = (labelText as NSString).size(withAttributes: [.font: labelFont])
        return NSSize(
            width: ceil(textSize.width) + requestedIconSize + 8 + 32,
            height: max(ceil(textSize.height), requestedIconSize) + 16
        )
    }
}

private final class CompactToolbarButton: NSButton {
    private let tint: NSColor
    private let labelText: String
    private let labelFont = NSFont.systemFont(ofSize: 12, weight: .medium)

    init(title: String, symbol: String? = nil, tint: NSColor = Palette.textSecondary) {
        self.tint = tint
        self.labelText = title
        super.init(frame: .zero)
        self.title = title
        translatesAutoresizingMaskIntoConstraints = false
        bezelStyle = .regularSquare
        isBordered = false
        wantsLayer = true
        focusRingType = .exterior
        layer?.cornerRadius = 16
        layer?.cornerCurve = .continuous
        setAccessibilityLabel(title)
        if let symbol {
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            imagePosition = .imageLeading
            imageScaling = .scaleProportionallyDown
            symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateLayer() {
        super.updateLayer()
        layer?.backgroundColor = (isHighlighted ? Palette.surfaceInset : Palette.surfaceElevated).cgColor
        let color = isEnabled ? tint : Palette.textTertiary.withAlphaComponent(0.55)
        contentTintColor = color
        attributedTitle = NSAttributedString(string: labelText, attributes: [
            .font: labelFont,
            .foregroundColor: color
        ])
    }

    override var intrinsicContentSize: NSSize {
        let textSize = (labelText as NSString).size(withAttributes: [.font: labelFont])
        let iconWidth: CGFloat = image == nil ? 0 : 20
        return NSSize(width: ceil(textSize.width) + 32 + iconWidth, height: ceil(textSize.height) + 16)
    }
}

private final class TrafficLightButton: NSButton {
    private let fillColor: NSColor

    init(color: NSColor, accessibilityLabel: String) {
        self.fillColor = color
        super.init(frame: .zero)
        title = ""
        translatesAutoresizingMaskIntoConstraints = false
        bezelStyle = .regularSquare
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 7
        setAccessibilityLabel(accessibilityLabel)
        widthAnchor.constraint(equalToConstant: 14).isActive = true
        heightAnchor.constraint(equalToConstant: 14).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateLayer() {
        super.updateLayer()
        layer?.backgroundColor = (isHighlighted ? fillColor.withAlphaComponent(0.65) : fillColor).cgColor
    }
}

private final class HeaderIconButton: NSButton {
    init(symbol: String, accessibilityLabel: String) {
        super.init(frame: .zero)
        title = ""
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: accessibilityLabel)
        imageScaling = .scaleProportionallyDown
        symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        contentTintColor = Palette.textSecondary
        toolTip = accessibilityLabel
        translatesAutoresizingMaskIntoConstraints = false
        bezelStyle = .regularSquare
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 7
        widthAnchor.constraint(equalToConstant: 28).isActive = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true
        setAccessibilityLabel(accessibilityLabel)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateLayer() {
        super.updateLayer()
        layer?.backgroundColor = (isHighlighted ? Palette.surfaceInset : NSColor.clear).cgColor
    }
}

// MARK: - Domain Models

private enum CreatorPreset: String, CaseIterable {
    case fastExport = "Fast Export"
    case aiArtwork = "AI Artwork"
    case socialMedia = "Social Media"
    case ultraQuality = "Ultra Quality"
    case portfolio = "Portfolio Mode"
    case framerWebflow = "Framer / Webflow"
    case websiteReady = "Website Ready"
    case custom = "Custom"

    var targetSize: String {
        switch self {
        case .fastExport: return "150kb"
        case .aiArtwork: return "2mb"
        case .socialMedia: return "900kb"
        case .ultraQuality: return "4mb"
        case .portfolio: return "1.5mb"
        case .framerWebflow: return "350kb"
        case .websiteReady: return "500kb"
        case .custom: return "750kb"
        }
    }

    var blurb: String {
        switch self {
        case .fastExport: return "Tiny shareable files"
        case .aiArtwork: return "Preserve painterly detail"
        case .socialMedia: return "Clean feed exports"
        case .ultraQuality: return "Gentle compression"
        case .portfolio: return "Crisp case studies"
        case .framerWebflow: return "Landing page assets"
        case .websiteReady: return "Fast pages, sharp visuals"
        case .custom: return "Tune every output detail"
        }
    }

    var symbol: String {
        switch self {
        case .fastExport: return "bolt.fill"
        case .aiArtwork: return "sparkles"
        case .socialMedia: return "rectangle.stack.fill"
        case .ultraQuality: return "diamond.fill"
        case .portfolio: return "square.inset.filled"
        case .framerWebflow: return "rectangle.compress.vertical"
        case .websiteReady: return "globe"
        case .custom: return "slider.horizontal.3"
        }
    }

    var savings: String {
        switch self {
        case .fastExport: return "Smallest target"
        case .aiArtwork: return "Detail first"
        case .socialMedia: return "Balanced target"
        case .ultraQuality: return "Gentle target"
        case .portfolio: return "Case-study target"
        case .framerWebflow: return "Web target"
        case .websiteReady: return "Web balanced"
        case .custom: return "Your settings"
        }
    }
}

private enum QueueFileStatus: String {
    case queued = "Queued"
    case processing = "Optimizing"
    case done = "Ready"
    case bestEffort = "Best effort"
    case skipped = "Skipped"
    case failed = "Needs attention"

    var tint: NSColor {
        switch self {
        case .queued: return Palette.textTertiary
        case .processing: return Palette.accent
        case .done: return Palette.success
        case .bestEffort: return Palette.warning
        case .skipped: return Palette.textTertiary
        case .failed: return Palette.danger
        }
    }

    var displayText: String { rawValue }
}

private struct QueueFile {
    let url: URL
    var status: QueueFileStatus = .queued
    var sourceSize: Int64 = 0
    var estimatedOutputSize: Int64? = nil
    var actualOutputSize: Int64? = nil
    var thumbnail: NSImage? = nil
    var error: String? = nil
    var outputURL: URL? = nil
}

private enum WorkspacePhase {
    case empty, imported, optimizing, complete
}

private final class MilestoneRailView: NSView {
    private let rows = NSStackView()
    private let titles = ["Files imported", "Intent selected", "Optimization started", "Optimization finished", "Ready to export"]
    private var icons: [NSImageView] = []
    private var labels: [NSTextField] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        rows.orientation = .vertical
        rows.alignment = .width
        rows.spacing = 12
        rows.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rows)
        for title in titles {
            let icon = makeSymbol("circle", size: 13, weight: .medium, color: Palette.textTertiary)
            let label = makeLabel(title, font: Typography.body, color: Palette.textTertiary)
            let row = NSStackView(views: [icon, label, NSView()])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 10
            rows.addArrangedSubview(row)
            icons.append(icon)
            labels.append(label)
        }
        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: leadingAnchor), rows.trailingAnchor.constraint(equalTo: trailingAnchor),
            rows.topAnchor.constraint(equalTo: topAnchor), rows.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func setCompleted(_ count: Int, active: Int? = nil) {
        for index in titles.indices {
            let done = index < count
            let isActive = active == index
            let name = done ? "checkmark.circle.fill" : (isActive ? "circle.dotted" : "circle")
            icons[index].image = NSImage(systemSymbolName: name, accessibilityDescription: titles[index])
            icons[index].contentTintColor = done ? Palette.success : (isActive ? Palette.accent : Palette.textTertiary)
            labels[index].textColor = done ? Palette.text : (isActive ? Palette.textSecondary : Palette.textTertiary)
            labels[index].font = isActive ? Typography.bodyMedium : Typography.body
        }
    }
}

private final class SuccessBannerView: NSView {
    let exportButton = PrimaryButton(title: "Export optimized files", symbol: "square.and.arrow.down")
    private let titleLabel = makeLabel("Your media is ready", font: NSFont.systemFont(ofSize: 24, weight: .semibold), color: Palette.text)
    private let detailLabel = makeLabel("Smaller files. Same creative impact.", font: Typography.body, color: Palette.textSecondary)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = Radius.lg
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = Palette.successSoft.cgColor
        let symbol = makeSymbol("checkmark.seal.fill", size: 31, weight: .medium, color: Palette.success)
        let copy = NSStackView(views: [titleLabel, detailLabel])
        copy.orientation = .vertical; copy.alignment = .leading; copy.spacing = 4
        let row = NSStackView(views: [symbol, copy, NSView(), exportButton])
        row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 16
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20), row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 18), row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18)
        ])
        setAccessibilityRole(.group)
        setAccessibilityLabel("Optimization complete")
    }

    required init?(coder: NSCoder) { fatalError() }
    func setDetail(_ text: String) { detailLabel.stringValue = text }
}

private final class ComparisonPreviewView: NSView {
    private let originalView = NSImageView()
    private let optimizedClip = NSView()
    private let optimizedView = NSImageView()
    private let divider = NSView()
    private let slider = NSSlider(value: 0.52, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let originalLabel = PillLabel(text: "Original")
    private let optimizedLabel = PillLabel(text: "Optimized", tint: Palette.success)
    private var clipWidth: NSLayoutConstraint!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = Radius.lg
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.clear.cgColor

        [originalView, optimizedView].forEach {
            $0.imageScaling = .scaleProportionallyUpOrDown
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.setContentHuggingPriority(.defaultLow, for: .horizontal)
            $0.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            $0.setContentHuggingPriority(.defaultLow, for: .vertical)
            $0.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        }
        optimizedClip.translatesAutoresizingMaskIntoConstraints = false
        optimizedClip.wantsLayer = true
        optimizedClip.layer?.masksToBounds = true
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.controlSize = .small
        slider.target = self
        slider.action = #selector(revealChanged)

        addSubview(originalView)
        addSubview(optimizedClip)
        optimizedClip.addSubview(optimizedView)
        addSubview(divider)
        addSubview(originalLabel)
        addSubview(optimizedLabel)
        addSubview(slider)
        clipWidth = optimizedClip.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 370),
            originalView.leadingAnchor.constraint(equalTo: leadingAnchor), originalView.trailingAnchor.constraint(equalTo: trailingAnchor),
            originalView.topAnchor.constraint(equalTo: topAnchor), originalView.bottomAnchor.constraint(equalTo: slider.topAnchor, constant: -10),
            optimizedClip.leadingAnchor.constraint(equalTo: leadingAnchor), optimizedClip.topAnchor.constraint(equalTo: topAnchor),
            optimizedClip.bottomAnchor.constraint(equalTo: slider.topAnchor, constant: -10), clipWidth,
            optimizedView.leadingAnchor.constraint(equalTo: leadingAnchor), optimizedView.widthAnchor.constraint(equalTo: widthAnchor),
            optimizedView.topAnchor.constraint(equalTo: topAnchor), optimizedView.bottomAnchor.constraint(equalTo: slider.topAnchor, constant: -10),
            divider.leadingAnchor.constraint(equalTo: optimizedClip.trailingAnchor, constant: -1), divider.widthAnchor.constraint(equalToConstant: 2),
            divider.topAnchor.constraint(equalTo: topAnchor, constant: 12), divider.bottomAnchor.constraint(equalTo: slider.topAnchor, constant: -22),
            originalLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), originalLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            optimizedLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12), optimizedLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            slider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16), slider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            slider.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
        setAccessibilityRole(.group)
        setAccessibilityLabel("Original and optimized image comparison")
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        clipWidth.constant = max(0, bounds.width * CGFloat(slider.doubleValue))
    }

    @objc private func revealChanged() {
        clipWidth.constant = max(0, bounds.width * CGFloat(slider.doubleValue))
        needsLayout = true
    }

    func set(original: NSImage?, optimized: NSImage?) {
        originalView.image = original
        optimizedView.image = optimized ?? original
        optimizedLabel.isHidden = optimized == nil
        divider.isHidden = optimized == nil
        slider.isEnabled = optimized != nil
    }
}

private struct CompressionSettings {
    var maxSize: String = "150kb"
    var outputFormat: String = "webp"
    var nameMode: String = "suffix"
    var outputFolder: URL? = nil
    var isBestQuality: Bool = false
    var minQuality: Int = 20
    var maxQuality: Int = 100
    var minSide: Int = 320
    var keepMetadata: Bool = false
    var background: String = "FFFFFF"
}

private struct CompressionRunResult {
    let lines: [String]
    let hadError: Bool
    let bestEffort: Bool
    let outputPath: URL?
}

// MARK: - Drop Zone

private final class DropZoneView: NSView {
    var onDrop: (([URL]) -> Void)?
    var onAddFiles: (() -> Void)?
    var onAddFolder: (() -> Void)?

    private let stack = NSStackView()
    private let orbView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "Drop Media to begin")
    private let subtitleLabel = NSTextField(wrappingLabelWithString: "Images and videos stay private on your Mac. Choose an intent when you’re ready.")
    private let actionRow = NSStackView()
    private let addFilesButton = PaddedActionButton(title: "Add Images", symbol: "photo.badge.plus", tint: Palette.accent)
    private let addFolderButton = PaddedActionButton(title: "Add Folder", symbol: "folder.badge.plus", tint: Palette.textSecondary)
    private let empty = true
    private var heightConstraint: NSLayoutConstraint!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = Radius.xl
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.borderColor = Palette.border.cgColor
        layer?.backgroundColor = Palette.surface.cgColor
        registerForDraggedTypes([.fileURL])
        setAccessibilityRole(.group)
        setAccessibilityLabel("Media import area")
        setAccessibilityHelp("Drop images or videos here, or choose files and folders from your Mac")

        orbView.image = NSImage(systemSymbolName: "photo.stack", accessibilityDescription: nil)
        orbView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 32, weight: .regular)
        orbView.contentTintColor = Palette.accent
        orbView.translatesAutoresizingMaskIntoConstraints = false
        orbView.heightAnchor.constraint(equalToConstant: 56).isActive = true

        titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = Palette.text
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        subtitleLabel.textColor = Palette.textSecondary
        subtitleLabel.alignment = .center
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.maximumNumberOfLines = 2

        addFilesButton.target = self
        addFilesButton.action = #selector(handleAddFiles)
        addFolderButton.target = self
        addFolderButton.action = #selector(handleAddFolder)

        actionRow.orientation = .horizontal
        actionRow.spacing = Spacing.md
        actionRow.translatesAutoresizingMaskIntoConstraints = false
        actionRow.addArrangedSubview(addFilesButton)
        actionRow.addArrangedSubview(addFolderButton)

        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = Spacing.lg
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        let textStack = NSStackView(views: [titleLabel, subtitleLabel])
        textStack.orientation = .vertical
        textStack.alignment = .centerX
        textStack.spacing = Spacing.xs
        textStack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(textStack)
        stack.addArrangedSubview(actionRow)

        heightConstraint = heightAnchor.constraint(equalToConstant: FigmaLayout.emptyDropHeight)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: Spacing.xl),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Spacing.xl),
            heightConstraint
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func handleAddFiles() { onAddFiles?() }
    @objc private func handleAddFolder() { onAddFolder?() }

    func setExpanded(_ expanded: Bool) {
        heightConstraint.constant = expanded ? FigmaLayout.emptyDropHeight : FigmaLayout.compactDropHeight
        titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .bold)
        titleLabel.stringValue = "Drop Media to begin"
        subtitleLabel.stringValue = "Images and videos stay private on your Mac. Choose an intent when you’re ready."
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        NSAnimationContext.runAnimationGroup { _ in
            NSAnimationContext.current.duration = MotionTokens.quick
            layer?.borderColor = Palette.accent.cgColor
            layer?.backgroundColor = Palette.accentSoft.cgColor
            layer?.shadowColor = Palette.accent.withAlphaComponent(0.45).cgColor
            layer?.shadowRadius = 24
            layer?.shadowOpacity = 1
            layer?.setAffineTransform(CGAffineTransform(scaleX: 1.008, y: 1.008))
        }
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        layer?.borderColor = Palette.border.cgColor
        layer?.backgroundColor = Palette.surface.cgColor
        layer?.shadowOpacity = 0
        layer?.setAffineTransform(.identity)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        layer?.borderColor = Palette.border.cgColor
        layer?.backgroundColor = Palette.surface.cgColor
        layer?.shadowOpacity = 0
        layer?.setAffineTransform(.identity)
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else { return false }
        onDrop?(items)
        return true
    }
}

// MARK: - Queue Grid Cell

private final class QueueItemView: NSView {
    private let thumbView = NSImageView()
    private let thumbBg = NSView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let sizeLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let progressBar = NSProgressIndicator()
    private let iconOverlay = NSImageView()

    var file: QueueFile? { didSet { configure() } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = Radius.sm
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderWidth = 0

        thumbBg.wantsLayer = true
        thumbBg.layer?.cornerRadius = 14
        thumbBg.layer?.cornerCurve = .continuous
        thumbBg.layer?.backgroundColor = Palette.surfaceInset.cgColor
        thumbBg.layer?.masksToBounds = true
        thumbBg.translatesAutoresizingMaskIntoConstraints = false
        addSubview(thumbBg)

        thumbView.imageScaling = .scaleProportionallyUpOrDown
        thumbView.translatesAutoresizingMaskIntoConstraints = false
        thumbView.wantsLayer = true
        thumbView.layer?.cornerRadius = 14
        thumbView.layer?.cornerCurve = .continuous
        thumbView.layer?.masksToBounds = true
        thumbBg.addSubview(thumbView)

        iconOverlay.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
        iconOverlay.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        iconOverlay.contentTintColor = Palette.textTertiary
        iconOverlay.translatesAutoresizingMaskIntoConstraints = false
        thumbBg.addSubview(iconOverlay)

        nameLabel.font = Typography.bodyMedium
        nameLabel.textColor = Palette.text
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(nameLabel)

        sizeLabel.font = Typography.caption
        sizeLabel.textColor = Palette.textSecondary
        sizeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sizeLabel)

        statusLabel.font = Typography.micro
        statusLabel.textColor = Palette.textTertiary
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.alignment = .right
        addSubview(statusLabel)

        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.style = .bar
        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 1
        progressBar.doubleValue = 0
        progressBar.controlSize = .small
        addSubview(progressBar)

        NSLayoutConstraint.activate([
            thumbBg.leadingAnchor.constraint(equalTo: leadingAnchor),
            thumbBg.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            thumbBg.widthAnchor.constraint(equalToConstant: 56),
            thumbBg.heightAnchor.constraint(equalToConstant: 56),
            thumbBg.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -12),

            thumbView.leadingAnchor.constraint(equalTo: thumbBg.leadingAnchor),
            thumbView.trailingAnchor.constraint(equalTo: thumbBg.trailingAnchor),
            thumbView.topAnchor.constraint(equalTo: thumbBg.topAnchor),
            thumbView.bottomAnchor.constraint(equalTo: thumbBg.bottomAnchor),

            iconOverlay.centerXAnchor.constraint(equalTo: thumbBg.centerXAnchor),
            iconOverlay.centerYAnchor.constraint(equalTo: thumbBg.centerYAnchor),

            nameLabel.leadingAnchor.constraint(equalTo: thumbBg.trailingAnchor, constant: 12),
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusLabel.leadingAnchor, constant: -8),

            sizeLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            sizeLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            sizeLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),

            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            statusLabel.topAnchor.constraint(equalTo: topAnchor, constant: 14),

            progressBar.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            progressBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseEnteredAndExited], owner: self))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        alphaValue = 0
        layer?.setAffineTransform(CGAffineTransform(translationX: 0, y: -7))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = MotionTokens.standard
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
            layer?.setAffineTransform(.identity)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = Palette.surfaceTinted.withAlphaComponent(0.55).cgColor
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.3).cgColor
        layer?.shadowRadius = 10
        layer?.shadowOpacity = 0.65
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.shadowOpacity = 0
    }

    private func configure() {
        guard let file else { return }
        nameLabel.stringValue = file.url.lastPathComponent
        if let output = file.actualOutputSize {
            sizeLabel.stringValue = "\(humanSize(file.sourceSize)) → \(humanSize(output))"
        } else if let estimate = file.estimatedOutputSize {
            sizeLabel.stringValue = "\(humanSize(file.sourceSize)) → ~\(humanSize(estimate))"
        } else {
            sizeLabel.stringValue = humanSize(file.sourceSize)
        }
        statusLabel.stringValue = file.status.displayText
        statusLabel.textColor = file.status.tint
        thumbView.image = file.thumbnail
        if file.thumbnail != nil {
            iconOverlay.isHidden = true
        } else {
            iconOverlay.isHidden = false
        }
        switch file.status {
        case .queued: progressBar.doubleValue = 0
        case .processing: progressBar.doubleValue = 0.6
        case .done, .bestEffort, .skipped, .failed: progressBar.doubleValue = 1
        }
        setAccessibilityRole(.group)
        setAccessibilityLabel("\(file.url.lastPathComponent), \(sizeLabel.stringValue), \(file.status.displayText)")
    }
}

// MARK: - Preset Card

private final class PresetCardView: NSButton {
    let preset: CreatorPreset
    private let titleLabel = NSTextField(labelWithString: "")
    private let blurbLabel = NSTextField(labelWithString: "")
    private let targetLabel = NSTextField(labelWithString: "")
    private let savingsLabel = NSTextField(labelWithString: "")
    private let iconView = NSImageView()

    var isSelectedPreset: Bool = false {
        didSet {
            updateAppearance()
            guard isSelectedPreset, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
            layer?.setAffineTransform(CGAffineTransform(scaleX: 0.985, y: 0.985))
            NSAnimationContext.runAnimationGroup { context in
                context.duration = MotionTokens.quick
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                layer?.setAffineTransform(.identity)
            }
        }
    }

    init(preset: CreatorPreset) {
        self.preset = preset
        super.init(frame: .zero)
        title = ""
        translatesAutoresizingMaskIntoConstraints = false
        bezelStyle = .regularSquare
        isBordered = false
        wantsLayer = true
        focusRingType = .exterior
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        titleLabel.stringValue = preset.rawValue
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = Palette.text
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        blurbLabel.stringValue = preset.blurb
        blurbLabel.font = Typography.caption
        blurbLabel.textColor = Palette.textSecondary
        blurbLabel.translatesAutoresizingMaskIntoConstraints = false

        targetLabel.stringValue = preset.targetSize.uppercased()
        targetLabel.font = Typography.micro
        targetLabel.textColor = Palette.textTertiary
        targetLabel.translatesAutoresizingMaskIntoConstraints = false

        savingsLabel.stringValue = preset.savings
        savingsLabel.font = Typography.micro
        savingsLabel.textColor = Palette.success
        savingsLabel.translatesAutoresizingMaskIntoConstraints = false
        savingsLabel.alignment = .right

        iconView.image = NSImage(systemSymbolName: preset.symbol, accessibilityDescription: nil)
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        iconView.contentTintColor = Palette.accent
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let header = NSStackView(views: [iconView, titleLabel])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8
        header.translatesAutoresizingMaskIntoConstraints = false

        let metrics = NSStackView(views: [targetLabel, savingsLabel])
        metrics.orientation = .horizontal
        metrics.alignment = .centerY
        metrics.spacing = 8
        metrics.distribution = .fillEqually
        metrics.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [header])
        stack.orientation = .vertical
        stack.spacing = 6
        stack.alignment = .width
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])

        updateAppearance()
        setAccessibilityLabel("\(preset.rawValue), \(preset.blurb), target \(preset.targetSize), \(preset.savings)")
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateLayer() {
        super.updateLayer()
    }

    private func updateAppearance() {
        guard let layer = layer else { return }
        if isSelectedPreset {
            layer.backgroundColor = Palette.accentSoft.cgColor
            layer.borderColor = Palette.accent.withAlphaComponent(0.6).cgColor
        } else if isHighlighted {
            layer.backgroundColor = Palette.surfaceInset.cgColor
            layer.borderColor = Palette.border.cgColor
        } else {
            layer.backgroundColor = Palette.surfaceElevated.cgColor
            layer.borderColor = Palette.borderSubtle.cgColor
        }
    }

    override func mouseDown(with event: NSEvent) {
        layer?.setAffineTransform(CGAffineTransform(scaleX: 0.975, y: 0.975))
        super.mouseDown(with: event)
        layer?.setAffineTransform(.identity)
        updateAppearance()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseEnteredAndExited], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isSelectedPreset else { return }
        layer?.backgroundColor = Palette.surfaceTinted.cgColor
    }

    override func mouseExited(with event: NSEvent) { updateAppearance() }
}

// MARK: - Format Helpers

private func humanSize(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

private func parseSize(_ text: String) -> Int64? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if trimmed.isEmpty { return nil }
    var numberString = ""
    var unit = ""
    for char in trimmed {
        if char.isNumber || char == "." {
            numberString.append(char)
        } else {
            unit.append(char)
        }
    }
    guard let value = Double(numberString) else { return nil }
    let multiplier: Double
    switch unit.trimmingCharacters(in: .whitespaces) {
    case "b", "": multiplier = 1
    case "kb": multiplier = 1024
    case "mb": multiplier = 1024 * 1024
    case "gb": multiplier = 1024 * 1024 * 1024
    default: return nil
    }
    return Int64(value * multiplier)
}

private let mediaToolPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
private let videoFileExtensions: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv", "webm", "wmv", "flv"]

private func videoToolsAvailable() -> Bool {
    let manager = FileManager.default
    let paths = mediaToolPath.split(separator: ":").map(String.init)
    return ["ffmpeg", "ffprobe"].allSatisfy { tool in
        paths.contains { manager.isExecutableFile(atPath: "\($0)/\(tool)") }
    }
}

private func mediaToolEnvironment() -> [String: String] {
    var environment = ProcessInfo.processInfo.environment
    environment["PATH"] = mediaToolPath
    return environment
}

// MARK: - Studio View Controller

private final class StudioViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let inspectorPanel = NSView()
    private var inspectorWidthConstraint: NSLayoutConstraint?
    private var queueWidthConstraint: NSLayoutConstraint?
    private var middleWidthConstraint: NSLayoutConstraint?
    private var inspectorIsCompact = false
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private var queueHeightConstraint: NSLayoutConstraint?
    private let tableContainer = NSView()
    private let tableStack = NSStackView()
    private let headerLabel = NSTextField(labelWithString: "Compression Queue")
    private let queueSubtitle = NSTextField(labelWithString: "Files appear here as you add them.")
    private let queueMetrics = NSStackView()
    private let metricSaved = StatTile(title: "Total Saved", value: "0 B", detail: "0%", valueColor: Palette.textTertiary)
    private let metricRatio = StatTile(title: "COMPRESSION RATIO", value: "0%", detail: "of original size", valueColor: Palette.textTertiary)
    private let metricFiles = StatTile(title: "FILES PROCESSED", value: "0 / 0", detail: "ready to export", valueColor: Palette.textTertiary)
    private let metricTime = StatTile(title: "ESTIMATED TIME", value: "0 Sec", detail: "0 files / s", valueColor: Palette.textTertiary)
    private let metricSpeed = StatTile(title: "PROCESSING SPEED", value: "—", detail: "files per second", valueColor: Palette.textSecondary)
    private let metricsRow = NSStackView()

    private let progressCard = GlassCard(cornerRadius: Radius.xl)
    private let progressCaption = NSTextField(labelWithString: "Ready when you are.")
    private let progressBar = NSProgressIndicator()
    private let progressActionRow = NSStackView()
    private let compressButton = CompactToolbarButton(title: "Compress Queue")
    private let stopButton = CompactToolbarButton(title: "Stop", tint: Palette.danger)
    private let clearButton = CompactToolbarButton(title: "Clear All")
    private let exportButton = CompactToolbarButton(title: "Download All")
    private let toolbarOpenButton = SecondaryButton(title: "Open", symbol: "folder", tint: Palette.textSecondary)
    private let toolbarSaveButton = PrimaryButton(title: "Save all", symbol: "square.and.arrow.down")

    private let dropZone = DropZoneView()
    private let queueCard = NSView()
    private let queueQueuedPill = PillLabel(text: "0 B queued", tint: Palette.textTertiary)
    private let queueEstimatedPill = PillLabel(text: "0 B Estimated", tint: Palette.textTertiary)
    private let queueSavedPill = PillLabel(text: "0 B Saved", tint: Palette.textTertiary)
    private let queueAddButton = PaddedActionButton(title: "Add Images", symbol: "photo.badge.plus", tint: Palette.accent, fontSize: 12, iconSize: 16)
    private let headerBrandLeft = NSStackView()
    private let headerBrandCenter = NSTextField(labelWithString: "LumaShrink")
    private let headerActions = NSStackView()

    private let presetsSectionTitle = NSTextField(labelWithString: "Creator Presets")
    private let presetsSubtitle = NSTextField(labelWithString: "")
    private let presetsGrid = NSStackView()
    private let customSizeField = NSTextField(string: "750 KB")
    private let customSizeRow = NSStackView()
    private let presetCards: [CreatorPreset: PresetCardView] = {
        var map: [CreatorPreset: PresetCardView] = [:]
        for preset in CreatorPreset.allCases {
            map[preset] = PresetCardView(preset: preset)
        }
        return map
    }()

    private let previewCard = GlassCard(cornerRadius: Radius.xl)
    private let previewTitle = NSTextField(labelWithString: "Preview")
    private let previewSubtitle = NSTextField(labelWithString: "Select a queued image to inspect compression detail.")
    private let comparisonPreview = ComparisonPreviewView()
    private let previewDetailLabel = NSTextField(wrappingLabelWithString: "")
    private let previewEmpty = NSTextField(labelWithString: "No image selected")

    private let logCard = GlassCard(cornerRadius: Radius.xl)
    private let logTitle = NSTextField(labelWithString: "Milestones")
    private let milestoneRail = MilestoneRailView()
    private let successBanner = SuccessBannerView()

    private let statusBadge = PillLabel(text: "Ready", symbol: "checkmark.circle.fill", tint: Palette.success)
    private let statusBanner = NSTextField(labelWithString: "Drop a few images to begin, or pick a creator preset below.")
    private let workspaceTitleLabel = makeLabel("Compression queue", font: NSFont.systemFont(ofSize: 23, weight: .semibold), color: Palette.text)
    private let workspaceSubtitleLabel = makeLabel("Add images, review savings, and export polished assets.", font: Typography.body, color: Palette.textSecondary)
    private let imageModeButton = ModeButton(title: "Image Compressing", symbol: "photo.badge.arrow.down")
    private let videoModeButton = ModeButton(title: "Video Compressing", symbol: "play.rectangle")
    private let formatModeButton = ModeButton(title: "Change Format", symbol: "pencil.and.outline")

    private var queue: [QueueFile] = []
    private var settings = CompressionSettings()
    private var activePreset: CreatorPreset = .fastExport

    // Advanced settings UI controls
    private let advancedToggle = SecondaryButton(title: "Show advanced", symbol: "slider.horizontal.3", tint: Palette.textSecondary)
    private let advancedPanel = NSStackView()
    private let formatLabel = NSTextField(labelWithString: "Output format")
    private let formatPopup = NSPopUpButton()
    private let smallestDimLabel = NSTextField(labelWithString: "Smallest dimension")
    private let smallestDimPopup = NSPopUpButton()
    private let qualityMinLabel = NSTextField(labelWithString: "Min quality")
    private let qualityMinPopup = NSPopUpButton()
    private let qualityMaxLabel = NSTextField(labelWithString: "Max quality")
    private let qualityMaxPopup = NSPopUpButton()
    private let namingLabel = NSTextField(labelWithString: "Naming")
    private let namingPopup = NSPopUpButton()
    private let keepMetadataCheck = NSButton(radioButtonWithTitle: "Yes", target: nil, action: nil)
    private let chooseOutputFolderButton = SecondaryButton(title: "Choose output folder", symbol: "folder", tint: Palette.accent)
    private let outputFolderPathLabel = NSTextField(labelWithString: "Save next to originals")
    private var isRunning = false
    private var stopRequested = false
    private var activeCompressionProcesses: [Process] = []
    private var compressionLock = NSLock()
    private var runStartedAt: Date?
    private var runTotalFiles = 0
    private var runCompleted = 0
    private var runSourceBytes: Int64 = 0
    private var runOutputBytes: Int64 = 0
    private var lastOutputFolder: URL?
    private var selectedFileIndex: Int? = nil
    private var workspacePhase: WorkspacePhase = .empty
    private var queuePanelCollapsed = false
    private var inspectorPanelCollapsed = false

    override func loadView() {
        let root = AppBackgroundView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800))
        view = root

        let header = buildHero()
        let modeSwitcher = buildModeSwitcher()
        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(header)
        root.addSubview(modeSwitcher)
        root.addSubview(content)

        let queueSection = buildQueueSection()
        content.addSubview(queueSection)

        let middle = NSStackView()
        middle.orientation = .vertical
        middle.alignment = .width
        middle.spacing = Spacing.md
        middle.translatesAutoresizingMaskIntoConstraints = false
        middle.addArrangedSubview(buildMetricsRow())
        middle.addArrangedSubview(buildPreviewCard())
        middle.addArrangedSubview(dropZone)
        middle.addArrangedSubview(successBanner)
        content.addSubview(middle)

        inspectorPanel.translatesAutoresizingMaskIntoConstraints = false
        inspectorPanel.wantsLayer = true
        inspectorPanel.layer?.backgroundColor = NSColor.clear.cgColor
        inspectorPanel.layer?.borderWidth = 0
        let inspectorStack = NSStackView()
        inspectorStack.orientation = .vertical
        inspectorStack.alignment = .width
        inspectorStack.spacing = Spacing.md
        inspectorStack.translatesAutoresizingMaskIntoConstraints = false
        inspectorStack.addArrangedSubview(buildPresetsSection())
        inspectorPanel.addSubview(inspectorStack)
        let inspectorDivider = NSView()
        inspectorDivider.translatesAutoresizingMaskIntoConstraints = false
        inspectorDivider.wantsLayer = true
        inspectorDivider.layer?.backgroundColor = NSColor(calibratedWhite: 0.76, alpha: 1).cgColor
        inspectorPanel.addSubview(inspectorDivider)
        content.addSubview(inspectorPanel)

        inspectorWidthConstraint = inspectorPanel.widthAnchor.constraint(equalToConstant: FigmaLayout.inspectorWidth)
        queueWidthConstraint = queueSection.widthAnchor.constraint(equalToConstant: FigmaLayout.queueWidth)
        middleWidthConstraint = middle.widthAnchor.constraint(equalToConstant: FigmaLayout.emptyDropWidth)
        inspectorWidthConstraint?.isActive = true
        queueWidthConstraint?.isActive = true
        middleWidthConstraint?.isActive = true
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 40),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -40),
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 29),
            header.heightAnchor.constraint(equalToConstant: 50),

            modeSwitcher.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            modeSwitcher.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 18),

            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 40),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -40),
            content.topAnchor.constraint(equalTo: modeSwitcher.bottomAnchor, constant: 32),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -22),

            queueSection.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            queueSection.topAnchor.constraint(equalTo: content.topAnchor),
            queueSection.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor),

            inspectorPanel.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            inspectorPanel.topAnchor.constraint(equalTo: content.topAnchor),
            inspectorPanel.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor),
            inspectorStack.leadingAnchor.constraint(equalTo: inspectorPanel.leadingAnchor, constant: 24),
            inspectorStack.trailingAnchor.constraint(equalTo: inspectorPanel.trailingAnchor),
            inspectorStack.topAnchor.constraint(equalTo: inspectorPanel.topAnchor),
            inspectorStack.bottomAnchor.constraint(lessThanOrEqualTo: inspectorPanel.bottomAnchor),
            inspectorDivider.leadingAnchor.constraint(equalTo: inspectorPanel.leadingAnchor),
            inspectorDivider.topAnchor.constraint(equalTo: inspectorPanel.topAnchor),
            inspectorDivider.bottomAnchor.constraint(equalTo: inspectorPanel.bottomAnchor),
            inspectorDivider.widthAnchor.constraint(equalToConstant: 1),

            middle.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            middle.topAnchor.constraint(equalTo: content.topAnchor),
            middle.leadingAnchor.constraint(greaterThanOrEqualTo: queueSection.trailingAnchor, constant: 28),
            middle.trailingAnchor.constraint(lessThanOrEqualTo: inspectorPanel.leadingAnchor, constant: -28),
            dropZone.widthAnchor.constraint(equalTo: middle.widthAnchor)
        ])

        dropZone.onAddFiles = { [weak self] in self?.addFiles() }
        dropZone.onAddFolder = { [weak self] in self?.addFolder() }
        dropZone.onDrop = { [weak self] urls in self?.addURLs(urls) }
        successBanner.exportButton.target = self
        successBanner.exportButton.action = #selector(downloadAll)

        applyActivePreset()
        advancedPanel.isHidden = false
        advancedToggle.isHidden = true
        refreshQueueTable()
        updateWorkspacePhase(.empty, animated: false)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let shouldCompact = view.bounds.width < 1120
        guard shouldCompact != inspectorIsCompact else { return }
        inspectorIsCompact = shouldCompact
        inspectorWidthConstraint?.constant = workspacePhase == .empty || inspectorPanelCollapsed ? 0 : (shouldCompact ? 300 : FigmaLayout.inspectorWidth)
    }

    private func updateWorkspacePhase(_ phase: WorkspacePhase, animated: Bool = true) {
        workspacePhase = phase
        let empty = phase == .empty
        let complete = phase == .complete
        dropZone.setExpanded(empty)
        dropZone.isHidden = !empty
        queueCard.isHidden = empty || queuePanelCollapsed
        metricsRow.isHidden = empty
        previewCard.isHidden = empty
        successBanner.isHidden = !complete
        toolbarSaveButton.isHidden = empty
        toolbarOpenButton.title = empty ? "Import" : "Add media"
        compressButton.isEnabled = !empty && !isRunning
        stopButton.isEnabled = isRunning
        clearButton.isEnabled = !empty && !isRunning
        exportButton.isEnabled = complete
        headerBrandLeft.isHidden = empty
        headerBrandCenter.isHidden = !empty
        headerActions.isHidden = empty
        switch phase {
        case .empty:
            milestoneRail.setCompleted(0)
        case .imported:
            milestoneRail.setCompleted(2)
        case .optimizing:
            milestoneRail.setCompleted(2, active: 2)
        case .complete:
            milestoneRail.setCompleted(5)
        }
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        let shouldHideInspector = view.bounds.width < 820 || empty || inspectorPanelCollapsed
        inspectorPanel.isHidden = shouldHideInspector
        inspectorWidthConstraint?.constant = shouldHideInspector ? 0 : FigmaLayout.inspectorWidth
        queueWidthConstraint?.constant = empty || queuePanelCollapsed ? 0 : FigmaLayout.queueWidth
        middleWidthConstraint?.constant = empty ? FigmaLayout.emptyDropWidth : 390
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        view.alphaValue = 0.94
        NSAnimationContext.runAnimationGroup { context in
            context.duration = MotionTokens.standard
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            view.animator().alphaValue = 1
        }
    }

    private func buildHero() -> NSView {
        let hero = NSView()
        hero.translatesAutoresizingMaskIntoConstraints = false

        let closeDot = TrafficLightButton(color: NSColor(calibratedRed: 1.0, green: 0.37, blue: 0.34, alpha: 1), accessibilityLabel: "Close window")
        let minimizeDot = TrafficLightButton(color: NSColor(calibratedRed: 1.0, green: 0.74, blue: 0.18, alpha: 1), accessibilityLabel: "Minimize window")
        let zoomDot = TrafficLightButton(color: NSColor(calibratedRed: 0.12, green: 0.72, blue: 0.29, alpha: 1), accessibilityLabel: "Zoom window")
        closeDot.target = self
        closeDot.action = #selector(closeWindow)
        minimizeDot.target = self
        minimizeDot.action = #selector(minimizeWindow)
        zoomDot.target = self
        zoomDot.action = #selector(zoomWindow)
        let leftSidebarIcon = HeaderIconButton(symbol: "sidebar.left", accessibilityLabel: "Show or hide compression queue")
        leftSidebarIcon.target = self
        leftSidebarIcon.action = #selector(toggleQueuePanel)
        let windowChrome = NSStackView(views: [closeDot, minimizeDot, zoomDot, leftSidebarIcon])
        windowChrome.orientation = .horizontal
        windowChrome.alignment = .centerY
        windowChrome.spacing = 8
        windowChrome.setCustomSpacing(16, after: zoomDot)
        windowChrome.translatesAutoresizingMaskIntoConstraints = false

        let rightSidebarIcon = HeaderIconButton(symbol: "sidebar.right", accessibilityLabel: "Show or hide creator presets")
        rightSidebarIcon.target = self
        rightSidebarIcon.action = #selector(toggleInspectorPanel)

        let brand = makeLabel("LumaShrink", font: NSFont.systemFont(ofSize: 16, weight: .bold), color: Palette.accent)
        headerBrandLeft.orientation = .horizontal
        headerBrandLeft.alignment = .centerY
        headerBrandLeft.spacing = 12
        headerBrandLeft.translatesAutoresizingMaskIntoConstraints = false
        headerBrandLeft.addArrangedSubview(brand)

        headerBrandCenter.font = NSFont.systemFont(ofSize: 16, weight: .bold)
        headerBrandCenter.textColor = Palette.accent
        headerBrandCenter.alignment = .center
        headerBrandCenter.translatesAutoresizingMaskIntoConstraints = false

        compressButton.target = self
        compressButton.action = #selector(startCompression)
        stopButton.target = self
        stopButton.action = #selector(stopCompression)
        clearButton.target = self
        clearButton.action = #selector(clearAll)
        exportButton.target = self
        exportButton.action = #selector(downloadAll)
        headerActions.orientation = .horizontal
        headerActions.spacing = Spacing.xs
        headerActions.alignment = .centerY
        headerActions.translatesAutoresizingMaskIntoConstraints = false
        [compressButton, stopButton, clearButton, exportButton].forEach(headerActions.addArrangedSubview)

        hero.addSubview(headerBrandLeft)
        hero.addSubview(headerBrandCenter)
        hero.addSubview(headerActions)
        hero.addSubview(windowChrome)
        hero.addSubview(rightSidebarIcon)
        NSLayoutConstraint.activate([
            windowChrome.leadingAnchor.constraint(equalTo: hero.leadingAnchor),
            windowChrome.centerYAnchor.constraint(equalTo: hero.centerYAnchor),
            rightSidebarIcon.trailingAnchor.constraint(equalTo: hero.trailingAnchor),
            rightSidebarIcon.centerYAnchor.constraint(equalTo: hero.centerYAnchor),
            headerBrandLeft.leadingAnchor.constraint(equalTo: windowChrome.trailingAnchor, constant: 16),
            headerBrandLeft.centerYAnchor.constraint(equalTo: hero.centerYAnchor),
            headerBrandCenter.centerXAnchor.constraint(equalTo: hero.centerXAnchor),
            headerBrandCenter.centerYAnchor.constraint(equalTo: hero.centerYAnchor),
            headerActions.trailingAnchor.constraint(equalTo: rightSidebarIcon.leadingAnchor, constant: -16),
            headerActions.centerYAnchor.constraint(equalTo: hero.centerYAnchor)
        ])
        return hero
    }

    @objc private func closeWindow() { view.window?.performClose(nil) }
    @objc private func minimizeWindow() { view.window?.miniaturize(nil) }
    @objc private func zoomWindow() { view.window?.zoom(nil) }

    @objc private func toggleQueuePanel() {
        guard workspacePhase != .empty else { return }
        queuePanelCollapsed.toggle()
        queueCard.isHidden = queuePanelCollapsed
        queueWidthConstraint?.constant = queuePanelCollapsed ? 0 : FigmaLayout.queueWidth
        animatePanelChange()
    }

    @objc private func toggleInspectorPanel() {
        guard workspacePhase != .empty else { return }
        inspectorPanelCollapsed.toggle()
        inspectorPanel.isHidden = inspectorPanelCollapsed
        inspectorWidthConstraint?.constant = inspectorPanelCollapsed ? 0 : FigmaLayout.inspectorWidth
        animatePanelChange()
    }

    private func animatePanelChange() {
        view.needsLayout = true
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            view.layoutSubtreeIfNeeded()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = MotionTokens.standard
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            view.animator().layoutSubtreeIfNeeded()
        }
    }

    private func buildModeSwitcher() -> NSView {
        let shell = NSView()
        shell.translatesAutoresizingMaskIntoConstraints = false
        shell.wantsLayer = true
        shell.layer?.cornerRadius = 28
        shell.layer?.cornerCurve = .continuous
        shell.layer?.backgroundColor = Palette.surfaceElevated.cgColor
        shell.layer?.borderWidth = 1
        shell.layer?.borderColor = Palette.border.cgColor

        let sections = NSStackView(views: [imageModeButton, videoModeButton, formatModeButton])
        sections.orientation = .horizontal
        sections.alignment = .centerY
        sections.spacing = 4
        sections.distribution = .fillEqually
        sections.translatesAutoresizingMaskIntoConstraints = false
        shell.addSubview(sections)
        NSLayoutConstraint.activate([
            sections.leadingAnchor.constraint(equalTo: shell.leadingAnchor, constant: 8),
            sections.trailingAnchor.constraint(equalTo: shell.trailingAnchor, constant: -8),
            sections.topAnchor.constraint(equalTo: shell.topAnchor, constant: 8),
            sections.bottomAnchor.constraint(equalTo: shell.bottomAnchor, constant: -8)
        ])
        shell.widthAnchor.constraint(equalToConstant: 520).isActive = true
        imageModeButton.target = self
        imageModeButton.action = #selector(showImageMode)
        videoModeButton.target = self
        videoModeButton.action = #selector(showVideoMode)
        formatModeButton.target = self
        formatModeButton.action = #selector(showFormatMode)
        imageModeButton.isActive = true
        return shell
    }

    @objc private func showImageMode() {
        imageModeButton.isActive = true
        videoModeButton.isActive = false
        formatModeButton.isActive = false
        activateWorkspace("optimize")
    }

    @objc private func showVideoMode() {
        imageModeButton.isActive = false
        videoModeButton.isActive = true
        formatModeButton.isActive = false
        activateWorkspace("video")
    }

    @objc private func showFormatMode() {
        imageModeButton.isActive = false
        videoModeButton.isActive = false
        formatModeButton.isActive = true
        activateWorkspace("convert")
    }

    func activateWorkspace(_ workspace: String) {
        switch workspace {
        case "convert":
            workspaceTitleLabel.stringValue = "Convert format"
            workspaceSubtitleLabel.stringValue = "Import media, choose the output format, and optimize in one pass."
            advancedPanel.isHidden = false
            formatPopup.becomeFirstResponder()
        case "resize":
            workspaceTitleLabel.stringValue = "Resize media"
            workspaceSubtitleLabel.stringValue = "Resize and optimize without creating another workflow."
            advancedPanel.isHidden = false
            smallestDimPopup.becomeFirstResponder()
        case "metadata":
            workspaceTitleLabel.stringValue = "Metadata cleaner"
            workspaceSubtitleLabel.stringValue = "Remove private metadata while optimizing your media."
            advancedPanel.isHidden = false
            keepMetadataCheck.state = .off
        case "video":
            workspaceTitleLabel.stringValue = "Video compressing"
            workspaceSubtitleLabel.stringValue = "Add videos and create smaller, shareable exports on your Mac."
            advancedPanel.isHidden = false
        default:
            workspaceTitleLabel.stringValue = "Optimize media"
            workspaceSubtitleLabel.stringValue = "Import, choose an intent, preview, optimize, and export."
        }
        advancedToggle.title = advancedPanel.isHidden ? "Show advanced" : "Hide advanced"
    }

    private func buildMetricsRow() -> NSStackView {
        metricsRow.orientation = .vertical
        metricsRow.spacing = Spacing.sm
        metricsRow.alignment = .width
        metricsRow.translatesAutoresizingMaskIntoConstraints = false
        let first = NSStackView(views: [metricSaved, metricRatio])
        let second = NSStackView(views: [metricFiles, metricTime])
        for row in [first, second] {
            row.orientation = .horizontal
            row.spacing = Spacing.sm
            row.alignment = .width
            row.distribution = .fillEqually
            metricsRow.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: metricsRow.widthAnchor).isActive = true
        }
        metricSaved.widthAnchor.constraint(equalTo: first.widthAnchor, multiplier: 0.5, constant: -6).isActive = true
        metricRatio.widthAnchor.constraint(equalTo: metricSaved.widthAnchor).isActive = true
        metricFiles.widthAnchor.constraint(equalTo: second.widthAnchor, multiplier: 0.5, constant: -6).isActive = true
        metricTime.widthAnchor.constraint(equalTo: metricFiles.widthAnchor).isActive = true
        return metricsRow
    }

    private func buildQueueSection() -> NSView {
        queueCard.translatesAutoresizingMaskIntoConstraints = false
        queueCard.wantsLayer = true
        queueCard.layer?.backgroundColor = NSColor.clear.cgColor

        headerLabel.font = NSFont.systemFont(ofSize: 16, weight: .bold)
        headerLabel.textColor = Palette.text
        let summaryRow = NSStackView(views: [queueQueuedPill, queueEstimatedPill, queueSavedPill])
        summaryRow.orientation = .horizontal
        summaryRow.spacing = Spacing.xs
        summaryRow.alignment = .centerY
        summaryRow.translatesAutoresizingMaskIntoConstraints = false
        queueAddButton.target = self
        queueAddButton.action = #selector(addFiles)
        let titleRow = NSStackView(views: [headerLabel, NSView(), queueAddButton])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 12
        titleRow.translatesAutoresizingMaskIntoConstraints = false
        let headerStack = NSStackView(views: [titleRow, summaryRow])
        headerStack.orientation = .vertical
        headerStack.spacing = 16
        headerStack.alignment = .width
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        tableView.headerView = nil
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.backgroundColor = .clear
        tableView.rowHeight = 74
        tableView.intercellSpacing = NSSize(width: 0, height: 10)
        tableView.selectionHighlightStyle = .none
        tableView.target = self
        tableView.doubleAction = #selector(revealSelected)
        let queueMenu = NSMenu(title: "File")
        let revealItem = queueMenu.addItem(withTitle: "Reveal in Finder", action: #selector(revealSelected), keyEquivalent: "")
        revealItem.target = self
        let exportItem = queueMenu.addItem(withTitle: "Show optimized file", action: #selector(showSelectedOutput), keyEquivalent: "")
        exportItem.target = self
        queueMenu.addItem(.separator())
        let removeItem = queueMenu.addItem(withTitle: "Remove from queue", action: #selector(removeSelected), keyEquivalent: "")
        removeItem.target = self
        tableView.menu = queueMenu
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("queue"))
        column.title = "Queue"
        tableView.addTableColumn(column)
        tableView.dataSource = self
        tableView.delegate = self

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.documentView = tableView
        queueHeightConstraint = scrollView.heightAnchor.constraint(equalToConstant: 140)
        queueHeightConstraint?.isActive = true

        let inner = NSStackView(views: [headerStack, scrollView])
        inner.orientation = .vertical
        inner.spacing = Spacing.md
        inner.translatesAutoresizingMaskIntoConstraints = false
        let divider = NSView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor(calibratedWhite: 0.76, alpha: 1).cgColor
        queueCard.addSubview(inner)
        queueCard.addSubview(divider)
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: queueCard.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: queueCard.trailingAnchor, constant: -24),
            inner.topAnchor.constraint(equalTo: queueCard.topAnchor),
            inner.bottomAnchor.constraint(equalTo: queueCard.bottomAnchor),
            divider.trailingAnchor.constraint(equalTo: queueCard.trailingAnchor),
            divider.topAnchor.constraint(equalTo: queueCard.topAnchor),
            divider.bottomAnchor.constraint(equalTo: queueCard.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1)
        ])
        return queueCard
    }

    private func buildPresetsSection() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        presetsSectionTitle.font = NSFont.systemFont(ofSize: 16, weight: .bold)
        presetsSectionTitle.textColor = Palette.text
        presetsSubtitle.font = Typography.caption
        presetsSubtitle.textColor = Palette.textSecondary
        let headerStack = NSStackView(views: [presetsSectionTitle, presetsSubtitle])
        headerStack.orientation = .vertical
        headerStack.spacing = 2
        headerStack.alignment = .leading
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        presetsGrid.orientation = .vertical
        presetsGrid.spacing = 8
        presetsGrid.alignment = .width
        presetsGrid.translatesAutoresizingMaskIntoConstraints = false
        let presets = CreatorPreset.allCases.filter { $0 != .websiteReady }
        for rowStart in stride(from: 0, to: presets.count, by: 2) {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 8
            row.distribution = .fillEqually
            row.alignment = .width
            row.translatesAutoresizingMaskIntoConstraints = false
            presetsGrid.addArrangedSubview(row)
            for index in rowStart..<min(rowStart + 2, presets.count) {
                let preset = presets[index]
                let card = presetCards[preset]!
                card.target = self
                card.action = #selector(handlePresetTap(_:))
                row.addArrangedSubview(card)
            }
            if row.arrangedSubviews.count == 1 { row.addArrangedSubview(NSView()) }
        }
        customSizeField.placeholderString = "e.g. 500 KB, 2 MB, or 90000 B"
        customSizeField.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        customSizeField.isBezeled = false
        customSizeField.drawsBackground = false
        customSizeField.target = self
        customSizeField.action = #selector(customSizeChanged)
        customSizeField.translatesAutoresizingMaskIntoConstraints = false
        let customFieldShell = NSView()
        customFieldShell.translatesAutoresizingMaskIntoConstraints = false
        customFieldShell.wantsLayer = true
        customFieldShell.layer?.cornerRadius = 10
        customFieldShell.layer?.cornerCurve = .continuous
        customFieldShell.layer?.backgroundColor = Palette.surfaceElevated.cgColor
        customFieldShell.layer?.borderWidth = 1
        customFieldShell.layer?.borderColor = Palette.borderSubtle.cgColor
        customFieldShell.addSubview(customSizeField)
        NSLayoutConstraint.activate([
            customSizeField.leadingAnchor.constraint(equalTo: customFieldShell.leadingAnchor, constant: 16),
            customSizeField.trailingAnchor.constraint(equalTo: customFieldShell.trailingAnchor, constant: -16),
            customSizeField.topAnchor.constraint(equalTo: customFieldShell.topAnchor, constant: 8),
            customSizeField.bottomAnchor.constraint(equalTo: customFieldShell.bottomAnchor, constant: -8)
        ])
        customSizeRow.orientation = .vertical
        customSizeRow.alignment = .width
        customSizeRow.spacing = 8
        customSizeRow.addArrangedSubview(makeLabel("Target size (B, KB, or MB)", font: NSFont.systemFont(ofSize: 12, weight: .medium), color: Palette.text))
        customSizeRow.addArrangedSubview(customFieldShell)
        customSizeRow.isHidden = true

        let stack = NSStackView(views: [headerStack, presetsGrid, customSizeRow])
        stack.orientation = .vertical
        stack.spacing = Spacing.md
        stack.alignment = .width
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Advanced section (collapsible)
        advancedPanel.orientation = .vertical
        advancedPanel.spacing = Spacing.md
        advancedPanel.alignment = .width
        advancedPanel.translatesAutoresizingMaskIntoConstraints = false
        advancedPanel.isHidden = true
        setupAdvancedControls()

        advancedToggle.target = self
        advancedToggle.action = #selector(toggleAdvanced)

        stack.addArrangedSubview(advancedToggle)
        stack.addArrangedSubview(advancedPanel)

        return stack
    }

    private func setupAdvancedControls() {
        formatPopup.addItems(withTitles: ["Smart WebP", "Auto", "Keep original", "JPEG", "PNG"])
        formatPopup.selectItem(at: 0)
        smallestDimPopup.addItems(withTitles: ["160 px", "320 px", "480 px", "640 px", "800 px"])
        smallestDimPopup.selectItem(at: 1)
        qualityMinPopup.addItems(withTitles: ["20", "40", "60", "80"])
        qualityMinPopup.selectItem(at: 0)
        qualityMaxPopup.addItems(withTitles: ["80", "90", "95", "100"])
        qualityMaxPopup.selectItem(at: 3)
        namingPopup.addItems(withTitles: ["Same name", "Suffix", "Overwrite"])
        namingPopup.selectItem(at: 1)
        keepMetadataCheck.state = .off
        keepMetadataCheck.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        chooseOutputFolderButton.target = self
        chooseOutputFolderButton.action = #selector(chooseOutputFolder)
        outputFolderPathLabel.font = Typography.caption
        outputFolderPathLabel.textColor = Palette.textSecondary

        for popup in [formatPopup, smallestDimPopup, namingPopup] {
            popup.controlSize = .small
            popup.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        }

        let formatAndSize = NSStackView(views: [
            labeledColumn("OUTPUT FORMAT", formatPopup),
            labeledColumn("Min Side", smallestDimPopup)
        ])
        formatAndSize.orientation = .horizontal
        formatAndSize.spacing = Spacing.md
        formatAndSize.alignment = .top
        formatAndSize.distribution = .fillEqually
        formatAndSize.translatesAutoresizingMaskIntoConstraints = false

        let metadataColumn = NSStackView(views: [
            makeLabel("Keep metadata", font: NSFont.systemFont(ofSize: 12, weight: .semibold), color: Palette.text),
            keepMetadataCheck
        ])
        metadataColumn.orientation = .vertical
        metadataColumn.spacing = 8
        metadataColumn.alignment = .leading
        metadataColumn.translatesAutoresizingMaskIntoConstraints = false

        let namingAndMetadata = NSStackView(views: [
            labeledColumn("Naming", namingPopup),
            metadataColumn
        ])
        namingAndMetadata.orientation = .horizontal
        namingAndMetadata.spacing = Spacing.md
        namingAndMetadata.alignment = .top
        namingAndMetadata.distribution = .fillEqually
        namingAndMetadata.translatesAutoresizingMaskIntoConstraints = false

        advancedPanel.addArrangedSubview(formatAndSize)
        advancedPanel.addArrangedSubview(namingAndMetadata)
        chooseOutputFolderButton.title = "Output Folder"
        chooseOutputFolderButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true
        advancedPanel.addArrangedSubview(labeledColumn("Save to", chooseOutputFolderButton))
    }

    private func labeledRow(_ label: String, _ control: NSView) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = Spacing.md
        row.translatesAutoresizingMaskIntoConstraints = false
        let l = NSTextField(labelWithString: label)
        l.font = Typography.cardTitle
        l.textColor = Palette.text
        l.widthAnchor.constraint(equalToConstant: 180).isActive = true
        row.addArrangedSubview(l)
        row.addArrangedSubview(control)
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return row
    }

    private func labeledColumn(_ label: String, _ control: NSView) -> NSView {
        let col = NSStackView()
        col.orientation = .vertical
        col.spacing = 4
        col.alignment = .leading
        col.translatesAutoresizingMaskIntoConstraints = false
        let l = NSTextField(labelWithString: label)
        l.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        l.textColor = Palette.text
        col.addArrangedSubview(l)
        col.addArrangedSubview(control)
        control.widthAnchor.constraint(greaterThanOrEqualToConstant: 145).isActive = true
        return col
    }

    @objc private func toggleAdvanced() {
        advancedPanel.isHidden.toggle()
        advancedToggle.title = advancedPanel.isHidden ? "Show advanced" : "Hide advanced"
    }

    private func buildPreviewAndProgressRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = Spacing.lg
        row.alignment = .top
        row.distribution = .fillEqually
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addArrangedSubview(buildPreviewCard())
        row.addArrangedSubview(buildProgressCard())
        row.addArrangedSubview(buildLogCard())
        return row
    }

    private func buildPreviewCard() -> NSView {
        previewTitle.stringValue = "Live Preview"
        previewTitle.font = Typography.cardTitle
        previewTitle.textColor = Palette.text
        previewSubtitle.isHidden = true
        let titleStack = NSStackView(views: [previewTitle])
        titleStack.orientation = .vertical
        titleStack.spacing = 2
        titleStack.alignment = .leading
        titleStack.translatesAutoresizingMaskIntoConstraints = false

        previewEmpty.font = Typography.body
        previewEmpty.textColor = Palette.textTertiary
        previewEmpty.alignment = .center
        previewEmpty.translatesAutoresizingMaskIntoConstraints = false

        previewDetailLabel.font = Typography.caption
        previewDetailLabel.textColor = Palette.textSecondary
        previewDetailLabel.translatesAutoresizingMaskIntoConstraints = false
        previewDetailLabel.maximumNumberOfLines = 2

        let stack = NSStackView(views: [titleStack, comparisonPreview, previewEmpty])
        stack.orientation = .vertical
        stack.spacing = Spacing.sm
        stack.alignment = .width
        stack.translatesAutoresizingMaskIntoConstraints = false
        previewCard.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: previewCard.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: previewCard.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: previewCard.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: previewCard.bottomAnchor, constant: -16)
        ])
        return previewCard
    }

    private func buildProgressCard() -> NSView {
        progressCaption.font = Typography.cardTitle
        progressCaption.textColor = Palette.text
        let titleStack = NSStackView(views: [progressCaption])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.translatesAutoresizingMaskIntoConstraints = false

        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.style = .bar
        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 1
        progressBar.doubleValue = 0
        progressBar.heightAnchor.constraint(equalToConstant: 6).isActive = true

        let statusBadgeRow = NSStackView(views: [statusBadge])
        statusBadgeRow.orientation = .horizontal
        statusBadgeRow.alignment = .centerY
        statusBadgeRow.spacing = Spacing.sm
        statusBadgeRow.translatesAutoresizingMaskIntoConstraints = false

        compressButton.target = self
        compressButton.action = #selector(startCompression)
        compressButton.keyEquivalent = "\r"
        stopButton.target = self
        stopButton.action = #selector(stopCompression)
        clearButton.target = self
        clearButton.action = #selector(clearAll)
        exportButton.target = self
        exportButton.action = #selector(downloadAll)

        progressActionRow.orientation = .vertical
        progressActionRow.spacing = Spacing.sm
        progressActionRow.alignment = .width
        progressActionRow.translatesAutoresizingMaskIntoConstraints = false
        progressActionRow.addArrangedSubview(compressButton)
        progressActionRow.addArrangedSubview(stopButton)
        progressActionRow.addArrangedSubview(exportButton)
        progressActionRow.addArrangedSubview(clearButton)

        let stack = NSStackView(views: [titleStack, statusBadgeRow, progressBar, progressActionRow])
        stack.orientation = .vertical
        stack.spacing = Spacing.md
        stack.alignment = .width
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: Spacing.lg, left: Spacing.lg, bottom: Spacing.lg, right: Spacing.lg)
        progressCard.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: progressCard.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: progressCard.trailingAnchor),
            stack.topAnchor.constraint(equalTo: progressCard.topAnchor),
            stack.bottomAnchor.constraint(equalTo: progressCard.bottomAnchor)
        ])
        return progressCard
    }

    private func buildLogCard() -> NSView {
        logTitle.font = Typography.cardTitle
        logTitle.textColor = Palette.text
        let titleStack = NSStackView(views: [logTitle])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.translatesAutoresizingMaskIntoConstraints = false

        let helper = makeWrappingLabel("LumaShrink keeps you oriented without exposing technical logs.", font: Typography.caption, color: Palette.textSecondary)
        let stack = NSStackView(views: [titleStack, helper, milestoneRail])
        stack.orientation = .vertical
        stack.spacing = Spacing.sm
        stack.alignment = .width
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: Spacing.lg, left: Spacing.lg, bottom: Spacing.lg, right: Spacing.lg)
        logCard.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: logCard.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: logCard.trailingAnchor),
            stack.topAnchor.constraint(equalTo: logCard.topAnchor),
            stack.bottomAnchor.constraint(equalTo: logCard.bottomAnchor)
        ])
        return logCard
    }

    // MARK: - Preset Actions

    @objc private func handlePresetTap(_ sender: PresetCardView) {
        activePreset = sender.preset
        applyActivePreset()
        if sender.preset == .custom {
            advancedPanel.isHidden = false
            advancedToggle.title = "Hide advanced"
            customSizeRow.isHidden = false
            customSizeField.becomeFirstResponder()
        } else {
            customSizeRow.isHidden = true
        }
        refreshQueueTable()
    }

    private func applyActivePreset() {
        for (preset, card) in presetCards {
            card.isSelectedPreset = (preset == activePreset)
        }
        settings.maxSize = activePreset == .custom ? customSizeField.stringValue : activePreset.targetSize
        for index in queue.indices { queue[index].estimatedOutputSize = estimateOutputSize(source: queue[index].sourceSize) }
        updateMetrics()
    }

    @objc private func customSizeChanged() {
        let value = customSizeField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard parseSize(value) != nil else {
            customSizeField.textColor = Palette.danger
            return
        }
        customSizeField.textColor = Palette.text
        settings.maxSize = value
        for index in queue.indices { queue[index].estimatedOutputSize = estimateOutputSize(source: queue[index].sourceSize) }
        refreshQueueTable()
    }

    // MARK: - Queue Management

    @objc func addFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image, .movie]
        if panel.runModal() == .OK {
            addURLs(panel.urls)
        }
    }

    @objc func addFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            addURLs([url])
        }
    }

    func addURLs(_ urls: [URL]) {
        var added = 0
        for url in urls {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if isDirectory, let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                for case let fileURL as URL in enumerator {
                    let ext = fileURL.pathExtension.lowercased()
                    let supported = ["jpg","jpeg","png","webp","bmp","tif","tiff","heic","mp4","mov","m4v"]
                    if supported.contains(ext) {
                        if !queue.contains(where: { $0.url == fileURL }) {
                            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                            var file = QueueFile(url: fileURL, sourceSize: size)
                            file.estimatedOutputSize = estimateOutputSize(source: size)
                            file.thumbnail = loadThumbnail(for: fileURL, size: NSSize(width: 88, height: 88))
                            queue.append(file)
                            added += 1
                        }
                    }
                }
            } else {
                let ext = url.pathExtension.lowercased()
                let supported = ["jpg","jpeg","png","webp","bmp","tif","tiff","heic","mp4","mov","m4v"]
                if supported.contains(ext) && !queue.contains(where: { $0.url == url }) {
                    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                    var file = QueueFile(url: url, sourceSize: size)
                    file.estimatedOutputSize = estimateOutputSize(source: size)
                    file.thumbnail = loadThumbnail(for: url, size: NSSize(width: 88, height: 88))
                    queue.append(file)
                    added += 1
                }
            }
        }
        refreshQueueTable()
        statusBanner.stringValue = added > 0 ? "Added \(added) file\(added == 1 ? "" : "s"). Choose a preset and start when ready." : "No supported files found."
        if !queue.isEmpty {
            updateWorkspacePhase(.imported)
            if selectedFileIndex == nil {
                selectedFileIndex = 0
                tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                updatePreview(for: queue[0])
            }
        }
    }

    private func loadThumbnail(for url: URL, size: NSSize) -> NSImage? {
        if ["mp4","mov","m4v"].contains(url.pathExtension.lowercased()) {
            return nil
        }
        guard let image = NSImage(contentsOf: url) else { return nil }
        let target = NSSize(width: 176, height: 176)
        image.size = target
        return image
    }

    private func estimateOutputSize(source: Int64) -> Int64? {
        guard let target = parseSize(settings.maxSize) else { return nil }
        return min(source, target)
    }

    @objc func clearAll() {
        queue.removeAll()
        refreshQueueTable()
        statusBanner.stringValue = "Queue cleared."
        lastOutputFolder = nil
        exportButton.contentTintColor = Palette.textTertiary
        toolbarSaveButton.isEnabled = false
        updateWorkspacePhase(.empty)
    }

    @objc func revealSelected() {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard row >= 0, row < queue.count else { return }
        NSWorkspace.shared.activateFileViewerSelecting([queue[row].url])
    }

    @objc private func showSelectedOutput() {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard row >= 0, row < queue.count, let output = queue[row].outputURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([output])
    }

    @objc private func removeSelected() {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard row >= 0, row < queue.count, !isRunning else { return }
        queue.remove(at: row)
        refreshQueueTable()
        updateWorkspacePhase(queue.isEmpty ? .empty : .imported)
    }

    // MARK: - Output Folder

    @objc func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            settings.outputFolder = url
            outputFolderPathLabel.stringValue = url.path
        }
    }

    @objc func openOutputFolder() {
        guard let folder = lastOutputFolder else { return }
        NSWorkspace.shared.open(folder)
    }

    @objc func downloadAll() {
        guard let folder = lastOutputFolder else { return }
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("luma-export-\(Int(Date().timeIntervalSince1970)).zip")
        try? FileManager.default.removeItem(at: temp)
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.arguments = ["-j", "-r", temp.path] + urls.map { $0.path }
            process.currentDirectoryURL = folder
            try process.run()
            process.waitUntilExit()
        } catch {}
        if FileManager.default.fileExists(atPath: temp.path) {
            NSWorkspace.shared.activateFileViewerSelecting([temp])
        } else {
            NSWorkspace.shared.open(folder)
        }
    }

    // MARK: - Compression

    @objc func startCompression() {
        guard !isRunning else { return }
        if queue.isEmpty {
            NSSound.beep()
            statusBanner.stringValue = "Add some images first."
            return
        }
        if queue.contains(where: { videoFileExtensions.contains($0.url.pathExtension.lowercased()) }) && !videoToolsAvailable() {
            let alert = NSAlert()
            alert.messageText = "Video tools are required"
            alert.informativeText = "Install FFmpeg and FFprobe, then reopen LumaShrink. Image compression is ready to use without them."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
        if settings.outputFolder == nil && namingPopup.titleOfSelectedItem == "Same name" {
            chooseOutputFolder()
        }
        settings.maxSize = activePreset == .custom ? customSizeField.stringValue : activePreset.targetSize
        let dimTitle = smallestDimPopup.titleOfSelectedItem ?? "320 px"
        settings.minSide = Int(dimTitle.replacingOccurrences(of: " px", with: "")) ?? 320
        settings.minQuality = Int(qualityMinPopup.titleOfSelectedItem ?? "20") ?? 20
        settings.maxQuality = Int(qualityMaxPopup.titleOfSelectedItem ?? "100") ?? 100
        let fmtTitle = formatPopup.titleOfSelectedItem ?? "Smart WebP"
        let formatMap = ["Smart WebP": "webp", "Auto": "auto", "Keep original": "keep", "JPEG": "jpeg", "PNG": "png"]
        settings.outputFormat = formatMap[fmtTitle] ?? "webp"
        settings.isBestQuality = false
        let namingMap = ["Same name": "same-name", "Suffix": "suffix", "Overwrite": "overwrite"]
        settings.nameMode = namingMap[namingPopup.titleOfSelectedItem ?? "Same name"] ?? "same-name"
        settings.keepMetadata = (keepMetadataCheck.state == .on)

        isRunning = true
        stopRequested = false
        runStartedAt = Date()
        runTotalFiles = queue.count
        runCompleted = 0
        runSourceBytes = 0
        runOutputBytes = 0
        for i in queue.indices { queue[i].status = .queued }
        refreshQueueTable()
        statusBadge.setText("Optimizing")
        statusBadge.layer?.backgroundColor = Palette.accent.withAlphaComponent(0.12).cgColor
        statusBadge.layer?.borderColor = NSColor.clear.cgColor
        compressButton.isEnabled = false
        stopButton.isEnabled = true
        updateWorkspacePhase(.optimizing)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.runCompression()
        }
    }

    @objc func stopCompression() {
        stopRequested = true
        compressionLock.lock()
        let procs = activeCompressionProcesses
        compressionLock.unlock()
        for p in procs where p.isRunning { p.terminate() }
    }

    private func runCompression() {
        let group = DispatchGroup()
        let semaphore = DispatchSemaphore(value: max(1, min(ProcessInfo.processInfo.activeProcessorCount, 4)))
        var failed = 0
        var bestEffort = 0
        var written: [URL] = []
        for index in queue.indices {
            if stopRequested { break }
            semaphore.wait()
            if stopRequested { semaphore.signal(); break }
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { group.leave(); semaphore.signal(); return }
                self.setStatus(index, .processing)
                let result = self.runOne(at: index)
                self.setResult(index, result: result)
                if let path = result.outputPath { written.append(path) }
                if result.hadError { failed += 1 }
                if result.bestEffort { bestEffort += 1 }
                semaphore.signal()
                group.leave()
            }
        }
        group.wait()
        DispatchQueue.main.async { [weak self] in
            self?.finishRun(written: written, failed: failed, bestEffort: bestEffort)
        }
    }

    private func runOne(at index: Int) -> CompressionRunResult {
        let file = queue[index]
        guard let resourceURL = Bundle.main.resourceURL else {
            return CompressionRunResult(lines: ["[ERROR] Missing runtime."], hadError: true, bestEffort: false, outputPath: nil)
        }
        let runtime = resourceURL.appendingPathComponent("runtime", isDirectory: true)
        let imageHelper = runtime.appendingPathComponent("lumashrink-image-helper/lumashrink-image-helper")
        let videoHelper = runtime.appendingPathComponent("lumashrink-video-helper/lumashrink-video-helper")
        let outputDir = settings.outputFolder ?? file.url.deletingLastPathComponent()
        let videoExtensions = ["mp4", "mov", "m4v", "avi", "mkv", "webm", "wmv", "flv"]
        if videoExtensions.contains(file.url.pathExtension.lowercased()) {
            let targetBytes = max(parseSize(settings.maxSize) ?? 0, 64 * 1024)
            let outputPath = outputDir.appendingPathComponent(file.url.deletingPathExtension().lastPathComponent + "_optimized.mp4")
            let process = Process()
            process.executableURL = videoHelper
            process.currentDirectoryURL = runtime
            process.environment = mediaToolEnvironment()
            process.arguments = [file.url.path, outputPath.path, "-t", String(targetBytes), "--keep-audio", settings.keepMetadata ? "--keep-metadata" : "--no-metadata"]
            let outPipe = Pipe(); let errPipe = Pipe()
            process.standardOutput = outPipe; process.standardError = errPipe
            do {
                try process.run(); process.waitUntilExit()
            } catch {
                return CompressionRunResult(lines: ["[ERROR] \(file.url.lastPathComponent): \(error.localizedDescription)"], hadError: true, bestEffort: false, outputPath: nil)
            }
            let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let lines = (stdout + "\n" + stderr).split(separator: "\n").map(String.init)
            let succeeded = process.terminationStatus == 0 && FileManager.default.fileExists(atPath: outputPath.path)
            return CompressionRunResult(lines: lines, hadError: !succeeded, bestEffort: false, outputPath: succeeded ? outputPath : nil)
        }
        var args: [String]
        if settings.nameMode != "overwrite" {
            args = [file.url.path, outputDir.path, "-s", settings.maxSize, "--format", settings.isBestQuality ? "webp" : settings.outputFormat, "--name-mode", settings.nameMode, "--min-quality", String(settings.minQuality), "--max-quality", String(settings.maxQuality), "--min-side", String(settings.minSide), "--background", "FFFFFF"]
        } else {
            args = [file.url.path, "-s", settings.maxSize, "--format", settings.isBestQuality ? "webp" : settings.outputFormat, "--name-mode", settings.nameMode, "--min-quality", String(settings.minQuality), "--max-quality", String(settings.maxQuality), "--min-side", String(settings.minSide), "--background", "FFFFFF"]
        }
        if settings.keepMetadata {
            args.append("--keep-metadata")
        }
        let process = Process()
        process.executableURL = imageHelper
        process.currentDirectoryURL = runtime
        process.arguments = args
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        do {
            try process.run()
            compressionLock.lock()
            activeCompressionProcesses.append(process)
            compressionLock.unlock()
            process.waitUntilExit()
            compressionLock.lock()
            activeCompressionProcesses.removeAll { $0 === process }
            compressionLock.unlock()
        } catch {
            return CompressionRunResult(lines: ["[ERROR] \(file.url.lastPathComponent): \(error.localizedDescription)"], hadError: true, bestEffort: false, outputPath: nil)
        }
        let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let lines = (stdout + "\n" + stderr).split(separator: "\n").map(String.init)
        var outputPath: URL? = nil
        for line in lines {
            if line.contains("->") && (line.contains(".webp") || line.contains(".jpg") || line.contains(".png")) {
                let parts = line.components(separatedBy: "->")
                if let last = parts.last {
                    let cleaned = last.trimmingCharacters(in: .whitespaces)
                    let url = cleaned.hasPrefix("/") ? URL(fileURLWithPath: cleaned) : URL(string: cleaned)
                    if let url, FileManager.default.fileExists(atPath: url.path) { outputPath = url }
                }
            }
        }
        let isError = process.terminationStatus != 0 || lines.contains(where: { $0.contains("[ERROR]") })
        let isBest = lines.contains(where: { $0.contains("[BEST EFFORT]") })
        return CompressionRunResult(lines: lines, hadError: isError, bestEffort: isBest, outputPath: outputPath)
    }

    private func setStatus(_ index: Int, _ status: QueueFileStatus) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.queue.indices.contains(index) {
                self.queue[index].status = status
                self.refreshQueueTable()
            }
        }
    }

    private func setResult(_ index: Int, result: CompressionRunResult) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.queue.indices.contains(index) else { return }
            if let path = result.outputPath,
               let size = try? path.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                self.queue[index].actualOutputSize = Int64(size)
                self.runSourceBytes += self.queue[index].sourceSize
                self.runOutputBytes += Int64(size)
                if self.lastOutputFolder == nil { self.lastOutputFolder = path.deletingLastPathComponent() }
                self.queue[index].outputURL = path
            }
            self.queue[index].status = result.hadError ? .failed : (result.bestEffort ? .bestEffort : .done)
            self.queue[index].error = result.hadError ? result.lines.first : nil
            self.runCompleted += 1
            self.refreshQueueTable()
            self.updateMetrics()
            for line in result.lines { self.appendLog(line) }
        }
    }

    private func finishRun(written: [URL], failed: Int, bestEffort: Int) {
        isRunning = false
        compressButton.isEnabled = !queue.isEmpty
        stopButton.isEnabled = false
        if !written.isEmpty {
            lastOutputFolder = written.first?.deletingLastPathComponent() ?? settings.outputFolder
            statusBanner.stringValue = "Done. \(written.count) file\(written.count == 1 ? "" : "s") exported to \(lastOutputFolder?.path ?? "your Mac")."
            statusBadge.setText("Ready")
            statusBadge.layer?.backgroundColor = Palette.success.withAlphaComponent(0.12).cgColor
            exportButton.contentTintColor = Palette.accent
            toolbarSaveButton.isEnabled = true
            let saved = max(0, runSourceBytes - runOutputBytes)
            successBanner.setDetail("\(written.count) file\(written.count == 1 ? "" : "s") ready · \(humanSize(saved)) saved")
            updateWorkspacePhase(.complete)
        } else {
            statusBanner.stringValue = failed > 0 ? "\(failed) file\(failed == 1 ? "" : "s") had issues." : "Nothing to export."
            statusBadge.setText(failed > 0 ? "Needs attention" : "Ready")
            updateWorkspacePhase(.imported)
        }
        progressBar.doubleValue = runTotalFiles > 0 ? Double(runCompleted) / Double(runTotalFiles) : 0
        updateMetrics()
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { queue.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = queue[row]
        let cell = QueueItemView(frame: .zero)
        cell.file = item
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let tableView = notification.object as? NSTableView ?? self.tableView
        let row = tableView.selectedRow
        guard row >= 0, row < queue.count else { return }
        selectedFileIndex = row
        updatePreview(for: queue[row])
    }

    private func refreshQueueTable() {
        tableView.reloadData()
        queueHeightConstraint?.constant = min(470, max(140, CGFloat(queue.count) * 84))
        let totalBytes = queue.reduce(Int64(0)) { $0 + $1.sourceSize }
        let estimatedBytes = queue.reduce(Int64(0)) { $0 + ($1.estimatedOutputSize ?? $1.sourceSize) }
        let savedBytes = max(0, totalBytes - estimatedBytes)
        queueQueuedPill.setText("\(humanSize(totalBytes)) queued")
        queueEstimatedPill.setText("\(humanSize(estimatedBytes)) Estimated")
        queueSavedPill.setText("\(humanSize(savedBytes)) Saved")
        queueSubtitle.stringValue = queue.isEmpty
            ? "0 B queued  ·  0 B estimated  ·  0 B saved"
            : "\(queue.count) item\(queue.count == 1 ? "" : "s") queued  ·  \(humanSize(totalBytes)) total"
        updateMetrics()
    }

    private func updateMetrics() {
        let totalSource = queue.reduce(Int64(0)) { $0 + $1.sourceSize }
        let totalEstimated = queue.reduce(Int64(0)) { $0 + ($1.estimatedOutputSize ?? $1.sourceSize) }
        let saved = max(0, totalSource - totalEstimated)
        let ratio = totalSource > 0 ? max(0, min(100, Int(round((1 - Double(totalEstimated) / Double(totalSource)) * 100)))) : 0
        metricSaved.setValue(humanSize(saved))
        metricSaved.setDetail("\(ratio)% smaller than originals")
        metricRatio.setValue("\(ratio)%")
        metricRatio.setDetail("of original size")
        metricFiles.setValue("\(runCompleted) / \(queue.count)")
        metricFiles.setDetail("\(queue.filter { $0.status == .done }.count) ready to export")
        if isRunning, let start = runStartedAt {
            let elapsed = max(0.1, Date().timeIntervalSince(start))
            let rate = Double(runCompleted) / elapsed
            let remaining = max(0, runTotalFiles - runCompleted)
            let eta = Int(Double(remaining) / max(rate, 0.001))
            metricTime.setValue("\(eta)s")
            metricTime.setDetail("remaining")
            metricSpeed.setValue(String(format: "%.1f/s", rate))
            metricSpeed.setDetail("files per second")
        } else {
            metricTime.setValue("0 Sec")
            metricTime.setDetail("\(queue.count) files in queue")
            metricSpeed.setValue(queue.isEmpty ? "—" : "Ready")
            metricSpeed.setDetail("files per second")
        }
    }

    private func updatePreview(for file: QueueFile) {
        previewTitle.stringValue = "Live Preview"
        previewSubtitle.stringValue = file.url.lastPathComponent
        if file.thumbnail != nil {
            previewEmpty.isHidden = true
        } else {
            previewEmpty.isHidden = false
        }
        let optimized = file.outputURL.flatMap(NSImage.init(contentsOf:))
        comparisonPreview.set(original: NSImage(contentsOf: file.url) ?? file.thumbnail, optimized: optimized)
        if let output = file.actualOutputSize {
            previewDetailLabel.stringValue = "\(humanSize(file.sourceSize)) → \(humanSize(output)) · \(savingPercent(source: file.sourceSize, output: output))% saved"
        } else if let estimate = file.estimatedOutputSize {
            previewDetailLabel.stringValue = "\(humanSize(file.sourceSize)) → ~\(humanSize(estimate))"
        } else {
            previewDetailLabel.stringValue = "\(humanSize(file.sourceSize))"
        }
    }

    private func savingPercent(source: Int64, output: Int64) -> Int {
        guard source > 0 else { return 0 }
        return max(0, min(100, Int(round((1 - Double(output) / Double(source)) * 100))))
    }

    // MARK: - Log

    private func appendLog(_ line: String) {
        AppLogger.shared.write(line)
    }

    // MARK: - Diagnostics

    func startupDiagnosticsReport() -> String? {
        guard let resourceURL = Bundle.main.resourceURL else { return "Runtime missing" }
        let runtime = resourceURL.appendingPathComponent("runtime", isDirectory: true)
        let helper = runtime.appendingPathComponent("lumashrink-image-helper/lumashrink-image-helper").path
        return FileManager.default.isExecutableFile(atPath: helper) ? "Runtime ready" : "Image helper missing"
    }

    func setStartupStatus(_ report: String) {
        statusBanner.stringValue = report
    }
}

// MARK: - Utility: Rename

private final class RenameViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let dropZone = DropZoneView()
    private let titleLabel = NSTextField(labelWithString: "Rename")
    private let subtitleLabel = NSTextField(labelWithString: "Change the file extension on a batch of files without touching the content.")
    private let formatLabel = NSTextField(labelWithString: "New extension")
    private let formatPopup = NSPopUpButton()
    private let chooseFilesButton = PrimaryButton(title: "Choose files", symbol: "square.and.arrow.up")
    private let applyButton = PrimaryButton(title: "Apply rename", symbol: "checkmark.circle.fill")
    private let clearButton = SecondaryButton(title: "Clear all", tint: Palette.textTertiary)
    private let listTable = NSTableView()
    private let listScroll = NSScrollView()
    private let statusBadge = PillLabel(text: "Ready", symbol: "checkmark.circle.fill", tint: Palette.success)
    private let fileCountLabel = NSTextField(labelWithString: "0 files")
    private let settingsCard = GlassCard(cornerRadius: Radius.xl)
    private let queueCard = GlassCard(cornerRadius: Radius.xl)
    private let successBanner = SuccessBannerView()
    private var files: [URL] = []

    override func loadView() {
        let root = AppBackgroundView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        root.translatesAutoresizingMaskIntoConstraints = false
        view = root

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder
        root.addSubview(scroll)
        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        let main = NSStackView()
        main.orientation = .vertical
        main.spacing = Spacing.lg
        main.alignment = .width
        main.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(main)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            main.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: Spacing.xl),
            main.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -Spacing.xl),
            main.topAnchor.constraint(equalTo: document.topAnchor, constant: Spacing.xl),
            main.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -Spacing.xl)
        ])

        // Hero
        let titleStack = NSStackView(views: [titleLabel, subtitleLabel])
        titleStack.orientation = .vertical
        titleStack.spacing = 4
        titleStack.alignment = .leading
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 26, weight: .semibold)
        titleLabel.textColor = Palette.text
        subtitleLabel.font = Typography.body
        subtitleLabel.textColor = Palette.textSecondary
        let hero = NSStackView(views: [titleStack, NSView(), statusBadge])
        hero.alignment = .centerY
        hero.spacing = Spacing.md
        hero.translatesAutoresizingMaskIntoConstraints = false
        main.addArrangedSubview(hero)
        main.addArrangedSubview(successBanner)
        successBanner.isHidden = true
        successBanner.exportButton.isHidden = true

        // Settings card
        let settingsHeader = NSTextField(labelWithString: "Choose the new extension")
        settingsHeader.font = Typography.sectionTitle
        settingsHeader.textColor = Palette.text
        let settingsSub = NSTextField(labelWithString: "Pick what you want the new file extension to be. LumaShrink will rename every queued file.")
        settingsSub.font = Typography.caption
        settingsSub.textColor = Palette.textSecondary
        let settingsHeaderStack = NSStackView(views: [settingsHeader, settingsSub])
        settingsHeaderStack.orientation = .vertical
        settingsHeaderStack.spacing = 2
        settingsHeaderStack.alignment = .leading
        settingsHeaderStack.translatesAutoresizingMaskIntoConstraints = false

        formatLabel.font = Typography.cardTitle
        formatLabel.textColor = Palette.text
        formatPopup.addItems(withTitles: ["jpg", "jpeg", "png", "webp", "heic", "tiff", "bmp", "gif"])
        formatPopup.selectItem(at: 0)
        formatPopup.translatesAutoresizingMaskIntoConstraints = false

        let formatRow = NSStackView(views: [formatLabel, formatPopup])
        formatRow.orientation = .horizontal
        formatRow.alignment = .centerY
        formatRow.spacing = Spacing.md
        formatRow.translatesAutoresizingMaskIntoConstraints = false
        formatPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true

        chooseFilesButton.target = self
        chooseFilesButton.action = #selector(chooseFiles)
        applyButton.target = self
        applyButton.action = #selector(applyRename)
        clearButton.target = self
        clearButton.action = #selector(clearAll)

        let actionRow = NSStackView(views: [chooseFilesButton, clearButton])
        actionRow.orientation = .horizontal
        actionRow.spacing = Spacing.sm
        actionRow.translatesAutoresizingMaskIntoConstraints = false

        let settingsInner = NSStackView(views: [settingsHeaderStack, formatRow, actionRow])
        settingsInner.orientation = .vertical
        settingsInner.spacing = Spacing.md
        settingsInner.alignment = .width
        settingsInner.translatesAutoresizingMaskIntoConstraints = false
        settingsInner.edgeInsets = NSEdgeInsets(top: Spacing.lg, left: Spacing.lg, bottom: Spacing.lg, right: Spacing.lg)
        settingsCard.addSubview(settingsInner)
        NSLayoutConstraint.activate([
            settingsInner.leadingAnchor.constraint(equalTo: settingsCard.leadingAnchor),
            settingsInner.trailingAnchor.constraint(equalTo: settingsCard.trailingAnchor),
            settingsInner.topAnchor.constraint(equalTo: settingsCard.topAnchor),
            settingsInner.bottomAnchor.constraint(equalTo: settingsCard.bottomAnchor)
        ])
        main.addArrangedSubview(settingsCard)

        // Drop zone
        dropZone.onAddFiles = { [weak self] in self?.chooseFiles() }
        dropZone.onDrop = { [weak self] urls in self?.addURLs(urls) }
        main.addArrangedSubview(dropZone)

        // Queue
        let queueHeader = NSTextField(labelWithString: "Queue")
        queueHeader.font = Typography.sectionTitle
        queueHeader.textColor = Palette.text
        let queueSub = NSTextField(labelWithString: "Files appear here as you add them.")
        queueSub.font = Typography.caption
        queueSub.textColor = Palette.textSecondary
        fileCountLabel.font = Typography.captionMedium
        fileCountLabel.textColor = Palette.textSecondary
        let queueHeaderStack = NSStackView(views: [queueHeader, queueSub])
        queueHeaderStack.orientation = .vertical
        queueHeaderStack.spacing = 2
        queueHeaderStack.alignment = .leading
        queueHeaderStack.translatesAutoresizingMaskIntoConstraints = false
        let queueCountStack = NSStackView(views: [fileCountLabel])
        queueCountStack.orientation = .horizontal
        queueCountStack.alignment = .centerY
        queueCountStack.translatesAutoresizingMaskIntoConstraints = false
        let queueHeaderRow = NSStackView(views: [queueHeaderStack, NSView(), queueCountStack])
        queueHeaderRow.alignment = .centerY
        queueHeaderRow.translatesAutoresizingMaskIntoConstraints = false

        listTable.headerView = nil
        listTable.usesAlternatingRowBackgroundColors = false
        listTable.backgroundColor = .clear
        listTable.rowHeight = 48
        listTable.selectionHighlightStyle = .regular
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        col.title = "File"
        listTable.addTableColumn(col)
        listTable.dataSource = self
        listTable.delegate = self
        listScroll.translatesAutoresizingMaskIntoConstraints = false
        listScroll.hasVerticalScroller = true
        listScroll.borderType = .noBorder
        listScroll.drawsBackground = false
        listScroll.documentView = listTable
        listScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true

        let applyRow = NSStackView(views: [applyButton])
        applyRow.orientation = .horizontal
        applyRow.alignment = .centerY
        applyRow.translatesAutoresizingMaskIntoConstraints = false

        let queueInner = NSStackView(views: [queueHeaderRow, listScroll, applyRow])
        queueInner.orientation = .vertical
        queueInner.spacing = Spacing.md
        queueInner.alignment = .width
        queueInner.translatesAutoresizingMaskIntoConstraints = false
        queueInner.edgeInsets = NSEdgeInsets(top: Spacing.lg, left: Spacing.lg, bottom: Spacing.lg, right: Spacing.lg)
        queueCard.addSubview(queueInner)
        NSLayoutConstraint.activate([
            queueInner.leadingAnchor.constraint(equalTo: queueCard.leadingAnchor),
            queueInner.trailingAnchor.constraint(equalTo: queueCard.trailingAnchor),
            queueInner.topAnchor.constraint(equalTo: queueCard.topAnchor),
            queueInner.bottomAnchor.constraint(equalTo: queueCard.bottomAnchor)
        ])
        main.addArrangedSubview(queueCard)
        updateState()
    }

    @objc func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { addURLs(panel.urls) }
    }

    func addURLs(_ urls: [URL]) {
        for url in urls where !files.contains(url) { files.append(url) }
        refresh()
        updateState()
    }

    @objc func clearAll() {
        files.removeAll()
        refresh()
        statusBadge.setText("Ready")
        successBanner.isHidden = true
        updateState()
    }

    private func refresh() {
        listTable.reloadData()
        fileCountLabel.stringValue = "\(files.count) file\(files.count == 1 ? "" : "s")"
    }

    @objc func applyRename() {
        let ext = formatPopup.titleOfSelectedItem ?? "jpg"
        var renamed = 0
        for url in files {
            let base = url.deletingPathExtension()
            let dest = base.appendingPathExtension(ext)
            do {
                try FileManager.default.moveItem(at: url, to: dest)
                renamed += 1
            } catch {}
        }
        files.removeAll()
        listTable.reloadData()
        successBanner.setDetail("\(renamed) file\(renamed == 1 ? "" : "s") renamed successfully")
        successBanner.isHidden = false
        statusBadge.setText("Complete")
        updateState()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { files.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTextField(labelWithString: files[row].lastPathComponent)
        cell.font = Typography.body
        cell.textColor = Palette.text
        return cell
    }

    private func updateState() {
        let empty = files.isEmpty
        settingsCard.isHidden = empty && successBanner.isHidden
        queueCard.isHidden = empty
        dropZone.setExpanded(empty)
        applyButton.isEnabled = !empty
    }
}

// MARK: - Video Compression

private struct VideoQueueFile {
    let url: URL
    var status: QueueFileStatus = .queued
    var sourceSize: Int64 = 0
    var estimatedOutputSize: Int64? = nil
    var actualOutputSize: Int64? = nil
}

private final class VideoCompressViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let dropZone = DropZoneView()
    private let hero = NSTextField(labelWithString: "")
    private let subhero = NSTextField(labelWithString: "")
    private let statusBadge = PillLabel(text: "Ready", symbol: "checkmark.circle.fill", tint: Palette.success)

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let queueCard = GlassCard(cornerRadius: Radius.xxl)

    private let presetCard = GlassCard(cornerRadius: Radius.xl)
    private let presetTitle = NSTextField(labelWithString: "Choose your look")
    private let presetSubtitle = NSTextField(labelWithString: "Pick the size that matches where your video will live.")
    private let presetGrid = NSStackView()
    private let presetButtons: [NSButton] = [
        makeVideoPresetButton(title: "Social share", subtitle: "20 MB", target: "20mb"),
        makeVideoPresetButton(title: "Portfolio", subtitle: "60 MB", target: "60mb"),
        makeVideoPresetButton(title: "Landing page", subtitle: "120 MB", target: "120mb"),
        makeVideoPresetButton(title: "Archive", subtitle: "500 MB", target: "500mb")
    ]
    private let advancedToggle = SecondaryButton(title: "Show advanced", symbol: "slider.horizontal.3", tint: Palette.textSecondary)
    private let advancedPanel = NSStackView()
    private let formatLabel = NSTextField(labelWithString: "Output format")
    private let formatPopup = NSPopUpButton()
    private let folderLabel = NSTextField(labelWithString: "Output folder")
    private let folderPopup = NSOpenPanel() // dummy, real logic uses choose button
    private let chooseFolderButton = SecondaryButton(title: "Choose", symbol: "folder", tint: Palette.accent)
    private let keepAudioCheck = NSButton(checkboxWithTitle: "Keep audio", target: nil, action: nil)
    private let keepMetadataCheck = NSButton(checkboxWithTitle: "Keep metadata", target: nil, action: nil)

    private let progressCard = GlassCard(cornerRadius: Radius.xl)
    private let progressCaption = NSTextField(labelWithString: "Ready when you are.")
    private let progressBar = NSProgressIndicator()
    private let progressStats = NSStackView()
    private let statCount = StatTile(title: "FILES", value: "0 / 0", detail: "ready to compress", valueColor: Palette.text)
    private let statSaved = StatTile(title: "SAVED", value: "0 B", detail: "vs original", valueColor: Palette.success)
    private let statRate = StatTile(title: "PROGRESS", value: "0%", detail: "complete", valueColor: Palette.accent)
    private let statTime = StatTile(title: "TIME LEFT", value: "—", detail: "0 files / s", valueColor: Palette.warning)
    private let compressButton = PrimaryButton(title: "Compress videos", symbol: "play.fill")
    private let stopButton = SecondaryButton(title: "Stop", symbol: "stop.fill", tint: Palette.danger)
    private let exportButton = SecondaryButton(title: "Export all", symbol: "square.and.arrow.down", tint: Palette.textSecondary)
    private let clearButton = SecondaryButton(title: "Clear all", tint: Palette.textTertiary)

    private let logCard = GlassCard(cornerRadius: Radius.xl)
    private let logTitle = NSTextField(labelWithString: "Activity")
    private let logTextView = NSTextView()
    private let logScroll = NSScrollView()

    private var queue: [VideoQueueFile] = []
    private var activeTarget: String = "20mb"
    private var outputFolder: URL? = nil
    private var isRunning = false
    private var stopRequested = false
    private var runStartedAt: Date?
    private var runTotal = 0
    private var runCompleted = 0
    private var runSourceBytes: Int64 = 0
    private var runOutputBytes: Int64 = 0
    private var lastOutputFolder: URL?

    override func loadView() {
        let root = AppBackgroundView(frame: NSRect(x: 0, y: 0, width: 1100, height: 760))
        root.translatesAutoresizingMaskIntoConstraints = false
        view = root

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder
        root.addSubview(scroll)
        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        let main = NSStackView()
        main.orientation = .vertical
        main.alignment = .width
        main.spacing = Spacing.xl
        main.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(main)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            main.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: Spacing.xl),
            main.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -Spacing.xl),
            main.topAnchor.constraint(equalTo: document.topAnchor, constant: Spacing.xl),
            main.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -Spacing.xl)
        ])

        main.addArrangedSubview(buildHero())
        main.addArrangedSubview(buildPresetsCard())
        main.addArrangedSubview(dropZone)
        main.addArrangedSubview(buildQueueSection())
        main.addArrangedSubview(buildProgressAndLogRow())

        dropZone.onAddFiles = { [weak self] in self?.chooseFiles() }
        dropZone.onDrop = { [weak self] urls in self?.addURLs(urls) }

        applyActivePreset()
        refreshTable()
        setupAdvancedPanel()
    }

    private func buildHero() -> NSView {
        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.spacing = 4
        textStack.alignment = .leading
        textStack.translatesAutoresizingMaskIntoConstraints = false
        hero.stringValue = "Compress videos"
        hero.font = NSFont.systemFont(ofSize: 26, weight: .semibold)
        hero.textColor = Palette.text
        subhero.stringValue = "Drop, choose a preset, compress. Local, private, and fast."
        subhero.font = Typography.body
        subhero.textColor = Palette.textSecondary
        textStack.addArrangedSubview(hero)
        textStack.addArrangedSubview(subhero)
        let h = NSStackView(views: [textStack, NSView(), statusBadge])
        h.alignment = .centerY
        h.spacing = Spacing.md
        h.translatesAutoresizingMaskIntoConstraints = false
        return h
    }

    private func buildPresetsCard() -> NSView {
        let header = NSStackView(views: [presetTitle, presetSubtitle])
        header.orientation = .vertical
        header.spacing = 2
        header.alignment = .leading
        header.translatesAutoresizingMaskIntoConstraints = false
        presetTitle.font = Typography.sectionTitle
        presetTitle.textColor = Palette.text
        presetSubtitle.font = Typography.caption
        presetSubtitle.textColor = Palette.textSecondary

        presetGrid.orientation = .horizontal
        presetGrid.spacing = Spacing.md
        presetGrid.alignment = .width
        presetGrid.distribution = .fillEqually
        presetGrid.translatesAutoresizingMaskIntoConstraints = false
        for btn in presetButtons {
            btn.target = self
            btn.action = #selector(presetTapped(_:))
            presetGrid.addArrangedSubview(btn)
        }
        advancedToggle.target = self
        advancedToggle.action = #selector(toggleAdvanced)

        advancedPanel.orientation = .vertical
        advancedPanel.spacing = Spacing.sm
        advancedPanel.alignment = .width
        advancedPanel.translatesAutoresizingMaskIntoConstraints = false
        advancedPanel.isHidden = true

        let inner = NSStackView(views: [header, presetGrid, advancedToggle, advancedPanel])
        inner.orientation = .vertical
        inner.spacing = Spacing.md
        inner.alignment = .width
        inner.translatesAutoresizingMaskIntoConstraints = false
        inner.edgeInsets = NSEdgeInsets(top: Spacing.lg, left: Spacing.lg, bottom: Spacing.lg, right: Spacing.lg)
        presetCard.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: presetCard.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: presetCard.trailingAnchor),
            inner.topAnchor.constraint(equalTo: presetCard.topAnchor),
            inner.bottomAnchor.constraint(equalTo: presetCard.bottomAnchor)
        ])
        return presetCard
    }

    private func setupAdvancedPanel() {
        formatLabel.font = Typography.cardTitle
        formatLabel.textColor = Palette.text
        formatPopup.addItems(withTitles: ["mp4 (H.264)", "mov (H.264)"])
        formatPopup.selectItem(at: 0)
        formatPopup.target = self
        formatPopup.action = #selector(advancedChanged)

        folderLabel.font = Typography.cardTitle
        folderLabel.textColor = Palette.text
        chooseFolderButton.target = self
        chooseFolderButton.action = #selector(chooseFolder)

        keepAudioCheck.state = .on
        keepAudioCheck.font = Typography.body
        keepAudioCheck.target = self
        keepAudioCheck.action = #selector(advancedChanged)
        keepMetadataCheck.state = .off
        keepMetadataCheck.font = Typography.body
        keepMetadataCheck.target = self
        keepMetadataCheck.action = #selector(advancedChanged)

        let formatRow = NSStackView(views: [formatLabel, formatPopup])
        formatRow.orientation = .horizontal
        formatRow.alignment = .centerY
        formatRow.spacing = Spacing.md
        formatRow.translatesAutoresizingMaskIntoConstraints = false

        let folderRow = NSStackView(views: [folderLabel, chooseFolderButton])
        folderRow.orientation = .horizontal
        folderRow.alignment = .centerY
        folderRow.spacing = Spacing.md
        folderRow.translatesAutoresizingMaskIntoConstraints = false

        let checksRow = NSStackView(views: [keepAudioCheck, keepMetadataCheck])
        checksRow.orientation = .horizontal
        checksRow.spacing = Spacing.lg
        checksRow.translatesAutoresizingMaskIntoConstraints = false

        advancedPanel.addArrangedSubview(formatRow)
        advancedPanel.addArrangedSubview(folderRow)
        advancedPanel.addArrangedSubview(checksRow)
    }

    @objc private func presetTapped(_ sender: NSButton) {
        activeTarget = sender.identifier?.rawValue ?? "20mb"
        applyActivePreset()
    }

    @objc private func toggleAdvanced() {
        advancedPanel.isHidden.toggle()
        advancedToggle.title = advancedPanel.isHidden ? "Show advanced" : "Hide advanced"
    }

    @objc private func advancedChanged() {
        // No-op for now, just update status
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            outputFolder = url
            appendLog("Output folder: \(url.path)")
        }
    }

    private func applyActivePreset() {
        for btn in presetButtons {
            let active = btn.identifier?.rawValue == activeTarget
            (btn as? VideoPresetButton)?.applyActive(active)
        }
    }

    private func buildQueueSection() -> NSView {
        let header = NSTextField(labelWithString: "Queue")
        header.font = Typography.sectionTitle
        header.textColor = Palette.text
        let sub = NSTextField(labelWithString: "Videos appear here as you add them.")
        sub.font = Typography.caption
        sub.textColor = Palette.textSecondary
        let headerStack = NSStackView(views: [header, sub])
        headerStack.orientation = .vertical
        headerStack.spacing = 2
        headerStack.alignment = .leading
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        let clearBtn = SecondaryButton(title: "Clear all", tint: Palette.textTertiary)
        clearBtn.target = self
        clearBtn.action = #selector(clearAll)
        let headerRow = NSStackView(views: [headerStack, NSView(), clearBtn])
        headerRow.alignment = .centerY
        headerRow.translatesAutoresizingMaskIntoConstraints = false

        tableView.headerView = nil
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.backgroundColor = .clear
        tableView.rowHeight = 60
        tableView.selectionHighlightStyle = .regular
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("video"))
        col.title = "Videos"
        tableView.addTableColumn(col)
        tableView.dataSource = self
        tableView.delegate = self
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.documentView = tableView
        scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true

        let inner = NSStackView(views: [headerRow, scrollView])
        inner.orientation = .vertical
        inner.spacing = Spacing.md
        inner.alignment = .width
        inner.translatesAutoresizingMaskIntoConstraints = false
        inner.edgeInsets = NSEdgeInsets(top: Spacing.lg, left: Spacing.lg, bottom: Spacing.lg, right: Spacing.lg)
        queueCard.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: queueCard.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: queueCard.trailingAnchor),
            inner.topAnchor.constraint(equalTo: queueCard.topAnchor),
            inner.bottomAnchor.constraint(equalTo: queueCard.bottomAnchor)
        ])
        return queueCard
    }

    private func buildProgressAndLogRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = Spacing.lg
        row.alignment = .top
        row.distribution = .fillEqually
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addArrangedSubview(buildProgressCard())
        row.addArrangedSubview(buildLogCard())
        return row
    }

    private func buildProgressCard() -> NSView {
        progressCaption.font = Typography.cardTitle
        progressCaption.textColor = Palette.text
        let titleStack = NSStackView(views: [progressCaption])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.translatesAutoresizingMaskIntoConstraints = false

        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.style = .bar
        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 1
        progressBar.doubleValue = 0
        progressBar.heightAnchor.constraint(equalToConstant: 6).isActive = true

        progressStats.orientation = .horizontal
        progressStats.spacing = Spacing.lg
        progressStats.alignment = .width
        progressStats.distribution = .fillEqually
        progressStats.translatesAutoresizingMaskIntoConstraints = false
        progressStats.addArrangedSubview(statCount)
        progressStats.addArrangedSubview(statSaved)
        progressStats.addArrangedSubview(statRate)
        progressStats.addArrangedSubview(statTime)

        compressButton.target = self
        compressButton.action = #selector(startCompression)
        compressButton.keyEquivalent = "\r"
        stopButton.target = self
        stopButton.action = #selector(stopCompression)
        clearButton.target = self
        clearButton.action = #selector(clearAll)
        exportButton.target = self
        exportButton.action = #selector(exportAll)

        let actionStack = NSStackView(views: [compressButton, stopButton, exportButton, clearButton])
        actionStack.orientation = .vertical
        actionStack.spacing = Spacing.sm
        actionStack.alignment = .width
        actionStack.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [titleStack, progressBar, progressStats, actionStack])
        stack.orientation = .vertical
        stack.spacing = Spacing.md
        stack.alignment = .width
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: Spacing.lg, left: Spacing.lg, bottom: Spacing.lg, right: Spacing.lg)
        progressCard.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: progressCard.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: progressCard.trailingAnchor),
            stack.topAnchor.constraint(equalTo: progressCard.topAnchor),
            stack.bottomAnchor.constraint(equalTo: progressCard.bottomAnchor)
        ])
        return progressCard
    }

    private func buildLogCard() -> NSView {
        logTitle.font = Typography.cardTitle
        logTitle.textColor = Palette.text
        let titleStack = NSStackView(views: [logTitle])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.translatesAutoresizingMaskIntoConstraints = false

        logTextView.isEditable = false
        logTextView.drawsBackground = true
        logTextView.backgroundColor = Palette.surfaceInset
        logTextView.textColor = Palette.text
        logTextView.font = Typography.monoSmall
        logTextView.textContainerInset = NSSize(width: 12, height: 10)
        logScroll.translatesAutoresizingMaskIntoConstraints = false
        logScroll.hasVerticalScroller = true
        logScroll.borderType = .noBorder
        logScroll.drawsBackground = false
        logScroll.documentView = logTextView
        logScroll.heightAnchor.constraint(equalToConstant: 200).isActive = true

        let stack = NSStackView(views: [titleStack, logScroll])
        stack.orientation = .vertical
        stack.spacing = Spacing.sm
        stack.alignment = .width
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: Spacing.lg, left: Spacing.lg, bottom: Spacing.lg, right: Spacing.lg)
        logCard.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: logCard.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: logCard.trailingAnchor),
            stack.topAnchor.constraint(equalTo: logCard.topAnchor),
            stack.bottomAnchor.constraint(equalTo: logCard.bottomAnchor)
        ])
        return logCard
    }

    // MARK: - File actions

    @objc func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie]
        if panel.runModal() == .OK { addURLs(panel.urls) }
    }

    func addURLs(_ urls: [URL]) {
        var added = 0
        for url in urls {
            let ext = url.pathExtension.lowercased()
            guard ["mp4","mov","m4v","avi","mkv","webm","wmv","flv"].contains(ext) else { continue }
            if queue.contains(where: { $0.url == url }) { continue }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            var file = VideoQueueFile(url: url, sourceSize: size)
            file.estimatedOutputSize = estimateOutputSize(source: size)
            queue.append(file)
            added += 1
        }
        refreshTable()
        if added > 0 {
            statusBadge.setText("\(added) added")
        }
    }

    private func estimateOutputSize(source: Int64) -> Int64? {
        guard let target = parseSize(activeTarget) else { return nil }
        return min(source, target)
    }

    @objc func clearAll() {
        queue.removeAll()
        refreshTable()
        statusBadge.setText("Ready")
        lastOutputFolder = nil
    }

    // MARK: - Compression

    @objc func startCompression() {
        guard !isRunning else { return }
        if queue.isEmpty {
            NSSound.beep()
            appendLog("Add some videos first.")
            return
        }
        if !videoToolsAvailable() {
            let alert = NSAlert()
            alert.messageText = "Video tools are required"
            alert.informativeText = "Install FFmpeg and FFprobe, then reopen LumaShrink."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
        isRunning = true
        stopRequested = false
        runStartedAt = Date()
        runTotal = queue.count
        runCompleted = 0
        runSourceBytes = 0
        runOutputBytes = 0
        for i in queue.indices { queue[i].status = .queued }
        refreshTable()
        statusBadge.setText("Compressing")
        compressButton.isEnabled = false
        stopButton.isEnabled = true
        appendLog("Starting compression for \(queue.count) video(s)…")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.runCompression()
        }
    }

    @objc func stopCompression() {
        stopRequested = true
        appendLog("Stop requested.")
    }

    @objc func exportAll() {
        guard let folder = lastOutputFolder else { return }
        NSWorkspace.shared.open(folder)
    }

    private func runCompression() {
        let group = DispatchGroup()
        let semaphore = DispatchSemaphore(value: 1)
        for index in queue.indices {
            if stopRequested { break }
            semaphore.wait()
            if stopRequested { semaphore.signal(); break }
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.compressOne(at: index)
                semaphore.signal()
                group.leave()
            }
        }
        group.wait()
        DispatchQueue.main.async { [weak self] in
            self?.finishRun()
        }
    }

    private func compressOne(at index: Int) {
        let file = queue[index]
        DispatchQueue.main.async { [weak self] in
            self?.queue[index].status = .processing
            self?.refreshTable()
        }
        guard let resourceURL = Bundle.main.resourceURL else {
            appendLog("[ERROR] Missing runtime")
            markFailed(at: index)
            return
        }
        let runtime = resourceURL.appendingPathComponent("runtime", isDirectory: true)
        let videoHelper = runtime.appendingPathComponent("lumashrink-video-helper/lumashrink-video-helper")
        let targetBytes = parseSize(activeTarget) ?? 20 * 1024 * 1024
        let outDir = outputFolder ?? file.url.deletingLastPathComponent()
        let outPath = outDir.appendingPathComponent(file.url.deletingPathExtension().lastPathComponent + "_compressed.mp4")
        let process = Process()
        process.executableURL = videoHelper
        process.currentDirectoryURL = runtime
        process.environment = mediaToolEnvironment()
        process.arguments = [
            file.url.path, outPath.path,
            "-t", String(targetBytes),
            keepAudioCheck.state == .on ? "--keep-audio" : "--no-audio",
            keepMetadataCheck.state == .on ? "--keep-metadata" : "--no-metadata"
        ]
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            appendLog("[ERROR] \(file.url.lastPathComponent): \(error.localizedDescription)")
            markFailed(at: index)
            return
        }
        let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let lines = stdout.split(separator: "\n").map(String.init) +
                    stderr.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        for line in lines { appendLog(line) }
        if FileManager.default.fileExists(atPath: outPath.path) {
            let size = (try? outPath.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            markDone(at: index, outputSize: size, outputPath: outPath)
        } else {
            markFailed(at: index)
        }
    }

    private func markDone(at index: Int, outputSize: Int64, outputPath: URL) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.queue[index].status = .done
            self.queue[index].actualOutputSize = outputSize
            self.runSourceBytes += self.queue[index].sourceSize
            self.runOutputBytes += outputSize
            self.runCompleted += 1
            if self.lastOutputFolder == nil { self.lastOutputFolder = outputPath.deletingLastPathComponent() }
            self.refreshTable()
            self.updateMetrics()
        }
    }

    private func markFailed(at index: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.queue[index].status = .failed
            self.runCompleted += 1
            self.refreshTable()
            self.updateMetrics()
        }
    }

    private func finishRun() {
        isRunning = false
        compressButton.isEnabled = !queue.isEmpty
        stopButton.isEnabled = false
        progressBar.doubleValue = runTotal > 0 ? Double(runCompleted) / Double(runTotal) : 0
        statusBadge.setText("Ready")
        appendLog("Done. \(runCompleted) of \(runTotal) video(s) processed.")
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { queue.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let file = queue[row]
        let cell = NSTextField(labelWithString: "\(file.url.lastPathComponent) — \(humanSize(file.sourceSize))")
        cell.font = Typography.body
        cell.textColor = file.status.tint
        return cell
    }

    private func refreshTable() {
        tableView.reloadData()
        updateMetrics()
    }

    private func updateMetrics() {
        let totalSource = queue.reduce(Int64(0)) { $0 + $1.sourceSize }
        let totalEstimated = queue.reduce(Int64(0)) { $0 + ($1.estimatedOutputSize ?? $1.sourceSize) }
        let saved = max(0, totalSource - totalEstimated)
        statCount.setValue("\(runCompleted) / \(queue.count)")
        statCount.setDetail("\(queue.filter { $0.status == .done }.count) ready")
        statSaved.setValue(humanSize(saved))
        statSaved.setDetail("vs original size")
        let ratio = totalSource > 0 ? max(0, min(100, Int(round((1 - Double(totalEstimated) / Double(totalSource)) * 100)))) : 0
        statRate.setValue("\(ratio)%")
        statRate.setDetail("smaller")
        if isRunning, let start = runStartedAt {
            let elapsed = max(0.1, Date().timeIntervalSince(start))
            let rate = Double(runCompleted) / elapsed
            let remaining = max(0, runTotal - runCompleted)
            let eta = Int(Double(remaining) / max(rate, 0.001))
            statTime.setValue("\(eta)s")
            statTime.setDetail(String(format: "%.1f files / s", rate))
        } else {
            statTime.setValue("Ready")
            statTime.setDetail("0 files / s")
        }
    }

    private func appendLog(_ line: String) {
        let color: NSColor
        if line.contains("[ERROR]") { color = Palette.danger }
        else if line.contains("[BEST EFFORT]") { color = Palette.warning }
        else if line.contains("[OK]") { color = Palette.success }
        else { color = Palette.text }
        let attr = NSAttributedString(string: line + "\n", attributes: [
            .font: Typography.monoSmall,
            .foregroundColor: color
        ])
        DispatchQueue.main.async { [weak self] in
            self?.logTextView.textStorage?.append(attr)
        }
    }
}

// MARK: - Video Preset Button

private final class VideoPresetButton: NSButton {
    private var isActiveState: Bool = false

    init(title: String, subtitle: String, target: String) {
        super.init(frame: .zero)
        self.title = "\(title)\n\(subtitle)"
        self.bezelStyle = .regularSquare
        self.isBordered = false
        self.identifier = NSUserInterfaceItemIdentifier(target)
        self.font = Typography.bodyMedium
        self.translatesAutoresizingMaskIntoConstraints = false
        self.wantsLayer = true
        self.layer?.cornerRadius = Radius.lg
        self.layer?.cornerCurve = .continuous
        self.layer?.borderWidth = 1
        self.heightAnchor.constraint(equalToConstant: 64).isActive = true
        applyActive(false)
    }

    required init?(coder: NSCoder) { fatalError() }

    func applyActive(_ active: Bool) {
        isActiveState = active
        if active {
            layer?.backgroundColor = Palette.accentSoft.cgColor
            layer?.borderColor = Palette.accent.withAlphaComponent(0.6).cgColor
            contentTintColor = Palette.accent
        } else {
            layer?.backgroundColor = Palette.surfaceElevated.cgColor
            layer?.borderColor = Palette.borderSubtle.cgColor
            contentTintColor = Palette.textSecondary
        }
    }
}

private func makeVideoPresetButton(title: String, subtitle: String, target: String) -> NSButton {
    return VideoPresetButton(title: title, subtitle: subtitle, target: target)
}

// MARK: - Sidebar

private final class SidebarCellView: NSTableCellView {
    var onClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

private final class SidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    enum Section: Int, CaseIterable {
        case studio = 0
        case utilities = 1
    }

    enum Item: Hashable {
        case section(Section)
        case optimize
        case convertFormat
        case metadataCleaner
    }

    var onSelect: (Item) -> Void

    private let outline = NSOutlineView()
    private let scroll = NSScrollView()
    private let header = NSTextField(labelWithString: "LumaShrink")
    private let subtitle = NSTextField(labelWithString: "Private media workspace")

    init(onSelect: @escaping (Item) -> Void) {
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 224, height: 700))
        root.wantsLayer = true
        root.layer?.backgroundColor = Palette.sidebar.cgColor
        root.translatesAutoresizingMaskIntoConstraints = false
        view = root

        let top = NSStackView(views: [header, subtitle])
        top.orientation = .vertical
        top.spacing = 2
        top.alignment = .leading
        top.translatesAutoresizingMaskIntoConstraints = false
        top.edgeInsets = NSEdgeInsets(top: Spacing.xl, left: Spacing.lg, bottom: Spacing.lg, right: Spacing.lg)
        root.addSubview(top)
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: root.topAnchor),
            top.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            top.trailingAnchor.constraint(equalTo: root.trailingAnchor)
        ])

        header.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        header.textColor = Palette.text
        subtitle.font = Typography.caption
        subtitle.textColor = Palette.textTertiary

        outline.translatesAutoresizingMaskIntoConstraints = false
        outline.headerView = nil
        outline.indentationPerLevel = 0
        outline.rowSizeStyle = .small
        outline.style = .sourceList
        outline.backgroundColor = .clear
        outline.usesAutomaticRowHeights = false
        outline.rowHeight = 32
        let studioCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        studioCol.title = "Item"
        outline.addTableColumn(studioCol)
        outline.dataSource = self
        outline.delegate = self

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.documentView = outline
        root.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: top.bottomAnchor, constant: Spacing.md),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        outline.reloadData()
        outline.expandItem(nil, expandChildren: true)
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return Section.allCases.count
        }
        if let section = item as? Section {
            switch section {
            case .studio: return 1
            case .utilities: return 2
            }
        }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return Section.allCases[index]
        }
        if let section = item as? Section {
            switch section {
            case .studio:
                return Item.optimize
            case .utilities:
                return [Item.convertFormat, .metadataCleaner][index]
            }
        }
        return Item.optimize
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return item is Section
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let cell = SidebarCellView()
        let label = NSTextField(labelWithString: "")
        label.font = Typography.bodyMedium
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label
        let labelLeading = label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6)
        NSLayoutConstraint.activate([
            labelLeading,
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -6)
        ])
        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(icon)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 22),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            icon.heightAnchor.constraint(equalToConstant: 14)
        ])
        if let section = item as? Section {
            switch section {
            case .studio:
                label.stringValue = "Workspace"
                label.font = Typography.micro
                label.textColor = Palette.textTertiary
                icon.isHidden = true
            case .utilities:
                label.stringValue = "Utilities"
                label.font = Typography.micro
                label.textColor = Palette.textTertiary
                icon.isHidden = true
            }
        } else if let leaf = item as? Item {
            labelLeading.constant = 44
            switch leaf {
            case .optimize:
                cell.identifier = NSUserInterfaceItemIdentifier("optimize")
                cell.onClick = { [weak self, weak cell] in self?.activate(.optimize, cell: cell) }
                label.stringValue = "Optimize"
                icon.image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: nil)
                icon.contentTintColor = Palette.accent
            case .convertFormat:
                cell.onClick = { [weak self, weak cell] in self?.activate(.convertFormat, cell: cell) }
                label.stringValue = "Convert Format"
                icon.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
                icon.contentTintColor = Palette.textSecondary
            case .metadataCleaner:
                cell.onClick = { [weak self, weak cell] in self?.activate(.metadataCleaner, cell: cell) }
                label.stringValue = "Metadata Cleaner"
                icon.image = NSImage(systemSymbolName: "hand.raised", accessibilityDescription: nil)
                icon.contentTintColor = Palette.textSecondary
            case .section:
                break
            }
        }
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        let row = outline.selectedRow
        guard row >= 0, let item = outline.item(atRow: row) as? Item else { return }
        onSelect(item)
    }

    private func activate(_ item: Item, cell: NSView?) {
        guard let cell else { return }
        let row = outline.row(for: cell)
        if row >= 0 { outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        onSelect(item)
    }

    func selectItem(_ item: Item) {
        outline.deselectAll(nil)
        let row = outline.row(forItem: item)
        if row >= 0 { outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
    }
}

// MARK: - Detail Container

private final class DetailContainerViewController: NSViewController {
    private let controllers: [NSViewController]
    private var visibleController: NSViewController?

    init(controllers: [NSViewController]) {
        self.controllers = controllers
        super.init(nibName: nil, bundle: nil)
        controllers.forEach(addChild)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 1100, height: 760))
        host.wantsLayer = true
        host.layer?.backgroundColor = Palette.window.cgColor
        view = host
    }

    func show(at index: Int) {
        guard controllers.indices.contains(index) else { return }
        loadViewIfNeeded()

        let next = controllers[index]
        guard visibleController !== next else { return }

        visibleController?.view.removeFromSuperview()
        let nextView = next.view
        nextView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(nextView)
        NSLayoutConstraint.activate([
            nextView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            nextView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            nextView.topAnchor.constraint(equalTo: view.topAnchor),
            nextView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        visibleController = next
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
    }
}

// MARK: - Split Controller
private final class AppSplitViewController: NSSplitViewController {
    let studio = StudioViewController()
    let sidebar: SidebarViewController

    init() {
        self.sidebar = SidebarViewController(onSelect: { _ in })
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()

        let controllers = [studio]
        let detailController = DetailContainerViewController(controllers: controllers)

        let detailItem = NSSplitViewItem(viewController: detailController)
        detailItem.minimumThickness = 640
        addSplitViewItem(detailItem)

        detailController.show(at: 0)
    }
}

// MARK: - App Delegate

final class ImageCompressorAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var split: AppSplitViewController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        split = AppSplitViewController()

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let windowWidth = min(FigmaLayout.canvasWidth, max(1100, screenFrame.width - 40))
        let windowHeight = min(FigmaLayout.canvasHeight, max(640, screenFrame.height - 24))

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "LumaShrink"
        window.contentMinSize = NSSize(width: 1100, height: 620)
        window.minSize = NSSize(width: 1100, height: 620)
        window.contentMaxSize = NSSize(width: screenFrame.width, height: screenFrame.height)
        window.maxSize = NSSize(width: screenFrame.width, height: screenFrame.height)
        window.isRestorable = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.toolbarStyle = .unifiedCompact
        window.backgroundColor = Palette.window
        window.isOpaque = true
        window.appearance = NSAppearance(named: .aqua)
        window.center()
        window.isReleasedWhenClosed = false
        window.contentViewController = split
        configureMainMenu()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let launchURLs = ProcessInfo.processInfo.arguments.dropFirst()
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        AppLogger.shared.write("Launch media: \(launchURLs.map(\.path).joined(separator: ", "))")
        if !launchURLs.isEmpty {
            split.studio.loadViewIfNeeded()
            split.studio.addURLs(launchURLs)
        }
        window.setContentSize(NSSize(width: windowWidth, height: windowHeight))
        window.center()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard !urls.isEmpty else { return }
        split.studio.loadViewIfNeeded()
        split.studio.addURLs(urls)
        window.makeKeyAndOrderFront(nil)
        application.activate(ignoringOtherApps: true)
    }

    @objc private func showGettingStarted() {
        let alert = NSAlert()
        alert.messageText = "Getting started with LumaShrink"
        alert.informativeText = "1. Add images, videos, or a folder.\n2. Choose an intent or open Advanced controls.\n3. Select an output folder.\n4. Optimize and review the before/after preview.\n\nLumaShrink creates suffixed copies by default. Keep your originals until you have reviewed every output."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Got it")
        alert.runModal()
    }

    @objc private func showDiagnosticLogs() {
        let logs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/ImageCompressor", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([logs])
    }

    @objc private func contactSupport() {
        guard let url = URL(string: "mailto:support@lumashrink.app?subject=LumaShrink%20support") else { return }
        NSWorkspace.shared.open(url)
    }

    private func configureMainMenu() {
        let main = NSMenu()

        // ── LumaShrink ──
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(title: "LumaShrink"); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About LumaShrink", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide LumaShrink", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit LumaShrink", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // ── File ──
        let fileItem = NSMenuItem(); main.addItem(fileItem)
        let fileMenu = NSMenu(title: "File"); fileItem.submenu = fileMenu
        addMenu("New Queue", to: fileMenu, key: "n", target: split.studio, action: #selector(StudioViewController.clearAll))
        fileMenu.addItem(.separator())
        addMenu("Add Media…", to: fileMenu, key: "o", target: split.studio, action: #selector(StudioViewController.addFiles))
        addMenu("Add Folder…", to: fileMenu, key: "o", modifiers: [.command, .shift], target: split.studio, action: #selector(StudioViewController.addFolder))
        fileMenu.addItem(.separator())
        addMenu("Choose Output Folder…", to: fileMenu, key: "s", target: split.studio, action: #selector(StudioViewController.chooseOutputFolder))
        addMenu("Open Output Folder", to: fileMenu, key: ".", target: split.studio, action: #selector(StudioViewController.openOutputFolder))
        fileMenu.addItem(.separator())
        addMenu("Close Window", to: fileMenu, key: "w", target: nil, action: #selector(NSWindow.performClose(_:)))

        // ── Actions ──
        let actionItem = NSMenuItem(); main.addItem(actionItem)
        let actionMenu = NSMenu(title: "Actions"); actionItem.submenu = actionMenu
        addMenu("Optimize Now", to: actionMenu, key: "\r", target: split.studio, action: #selector(StudioViewController.startCompression))
        addMenu("Clear Queue", to: actionMenu, key: "\u{8}", modifiers: [.command, .shift], target: split.studio, action: #selector(StudioViewController.clearAll))

        // ── Edit ──
        let editItem = NSMenuItem(); main.addItem(editItem)
        let editMenu = NSMenu(title: "Edit"); editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        // ── View ──
        let viewItem = NSMenuItem(); main.addItem(viewItem)
        let viewMenu = NSMenu(title: "View"); viewItem.submenu = viewMenu
        viewMenu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")

        // ── Window ──
        let windowItem = NSMenuItem(); main.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window"); windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu

        // ── Help ──
        let helpItem = NSMenuItem(); main.addItem(helpItem)
        let helpMenu = NSMenu(title: "Help"); helpItem.submenu = helpMenu
        addMenu("Getting Started", to: helpMenu, key: "?", modifiers: [.command, .shift], target: self, action: #selector(showGettingStarted))
        addMenu("Show Diagnostic Logs", to: helpMenu, key: "", modifiers: [], target: self, action: #selector(showDiagnosticLogs))
        helpMenu.addItem(.separator())
        addMenu("Contact Support", to: helpMenu, key: "", modifiers: [], target: self, action: #selector(contactSupport))

        NSApp.mainMenu = main
    }

    private func addMenu(_ title: String, to menu: NSMenu, key: String, modifiers: NSEvent.ModifierFlags = [.command], target: AnyObject?, action: Selector?) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        menu.addItem(item)
    }
}

@main
enum ImageCompressorMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = ImageCompressorAppDelegate()
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        _ = NSApp
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

// MARK: - NSStackView edgeInsets extension bridge

// MARK: - Studio expose for menu

extension ImageCompressorAppDelegate {
    fileprivate func studio() -> StudioViewController { split.studio }
}
