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
    static let window = NSColor(calibratedRed: 0.043, green: 0.047, blue: 0.055, alpha: 1.0)
    static let sidebar = NSColor(calibratedRed: 0.063, green: 0.071, blue: 0.082, alpha: 1.0)

    // Surfaces
    static let surface = NSColor(calibratedRed: 0.070, green: 0.075, blue: 0.086, alpha: 0.96)
    static let surfaceElevated = NSColor(calibratedRed: 0.095, green: 0.101, blue: 0.114, alpha: 1.0)
    static let surfaceTinted = NSColor(calibratedRed: 0.105, green: 0.113, blue: 0.129, alpha: 0.92)
    static let surfaceInset = NSColor(calibratedRed: 0.057, green: 0.061, blue: 0.070, alpha: 1.0)

    // Borders
    static let border = NSColor(calibratedRed: 0.185, green: 0.195, blue: 0.215, alpha: 1.0)
    static let borderSubtle = NSColor(calibratedRed: 0.135, green: 0.145, blue: 0.162, alpha: 1.0)

    // Text
    static let text = NSColor(calibratedWhite: 0.94, alpha: 1.0)
    static let textSecondary = NSColor(calibratedWhite: 0.66, alpha: 1.0)
    static let textTertiary = NSColor(calibratedWhite: 0.44, alpha: 1.0)
    static let textOnAccent = NSColor.white

    // Accent
    static let accent = NSColor(calibratedRed: 0.20, green: 0.55, blue: 0.98, alpha: 1.0)
    static let accentHover = NSColor(calibratedRed: 0.28, green: 0.61, blue: 1.0, alpha: 1.0)
    static let accentPressed = NSColor(calibratedRed: 0.14, green: 0.45, blue: 0.87, alpha: 1.0)
    static let accentSoft = NSColor(calibratedRed: 0.20, green: 0.55, blue: 0.98, alpha: 0.14)
    static let accentSoftPressed = NSColor(calibratedRed: 0.20, green: 0.55, blue: 0.98, alpha: 0.24)

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
    static let sectionTitle = NSFont.systemFont(ofSize: 20, weight: .semibold)
    static let cardTitle = NSFont.systemFont(ofSize: 15, weight: .semibold)
    static let body = NSFont.systemFont(ofSize: 13, weight: .regular)
    static let bodyMedium = NSFont.systemFont(ofSize: 13, weight: .medium)
    static let caption = NSFont.systemFont(ofSize: 12, weight: .regular)
    static let captionMedium = NSFont.systemFont(ofSize: 12, weight: .medium)
    static let micro = NSFont.systemFont(ofSize: 11, weight: .medium)
    static let monoSmall = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    static let display = NSFont.systemFont(ofSize: 34, weight: .semibold)
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
            NSColor(calibratedRed: 0.055, green: 0.060, blue: 0.070, alpha: 1.0).cgColor,
            NSColor(calibratedRed: 0.039, green: 0.043, blue: 0.051, alpha: 1.0).cgColor,
            NSColor(calibratedRed: 0.027, green: 0.030, blue: 0.036, alpha: 1.0).cgColor
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
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        layer?.borderColor = Palette.borderSubtle.cgColor
        layer?.backgroundColor = Palette.surface.cgColor
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.32).cgColor
        layer?.shadowOffset = CGSize(width: 0, height: -1)
        layer?.shadowRadius = 14
        layer?.shadowOpacity = 1
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
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
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
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
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
        layer?.backgroundColor = NSColor.clear.cgColor

        titleLabel.stringValue = title
        titleLabel.font = Typography.micro
        titleLabel.textColor = Palette.textTertiary
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        valueLabel.stringValue = value
        valueLabel.font = Typography.display
        valueLabel.textColor = valueColor
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        detailLabel.stringValue = detail
        detailLabel.font = Typography.caption
        detailLabel.textColor = Palette.textSecondary
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(valueLabel)
        addSubview(detailLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            valueLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: Spacing.xs),
            valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            detailLabel.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: Spacing.xxs),
            detailLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            detailLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func setValue(_ value: String) { valueLabel.stringValue = value }
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
        if let symbol { configureSymbol(symbol) }
    }
    required init?(coder: NSCoder) { fatalError() }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        bezelStyle = .regularSquare
        isBordered = false
        wantsLayer = true
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
        heightAnchor.constraint(equalToConstant: 40).isActive = true
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
}

private final class SecondaryButton: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }
    convenience init(title: String, symbol: String? = nil, tint: NSColor = Palette.text) {
        self.init(frame: .zero)
        self.title = title
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
        layer?.cornerRadius = Radius.md
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: Typography.bodyMedium,
                .foregroundColor: tint
            ]
        )
        heightAnchor.constraint(equalToConstant: 40).isActive = true
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

    var targetSize: String {
        switch self {
        case .fastExport: return "150kb"
        case .aiArtwork: return "2mb"
        case .socialMedia: return "900kb"
        case .ultraQuality: return "4mb"
        case .portfolio: return "1.5mb"
        case .framerWebflow: return "350kb"
        case .websiteReady: return "500kb"
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
        }
    }

    var savings: String {
        switch self {
        case .fastExport: return "Saves ~95%"
        case .aiArtwork: return "Saves ~60%"
        case .socialMedia: return "Saves ~75%"
        case .ultraQuality: return "Saves ~40%"
        case .portfolio: return "Saves ~70%"
        case .framerWebflow: return "Saves ~88%"
        case .websiteReady: return "Saves ~85%"
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
}

private struct CompressionSettings {
    var maxSize: String = "150kb"
    var outputFormat: String = "best_quality"
    var nameMode: String = "same-name"
    var outputFolder: URL? = nil
    var isBestQuality: Bool = true
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
    private let titleLabel = NSTextField(labelWithString: "Drop images to begin")
    private let subtitleLabel = NSTextField(wrappingLabelWithString: "LumaShrink keeps every pixel on your Mac while preparing creator-ready exports.")
    private let actionRow = NSStackView()
    private let addFilesButton = SecondaryButton(title: "Choose images", symbol: "square.and.arrow.up", tint: Palette.accent)
    private let addFolderButton = SecondaryButton(title: "Choose folder", symbol: "folder", tint: Palette.textSecondary)
    private let empty = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = Radius.xxl
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1.5
        layer?.borderColor = Palette.border.cgColor
        layer?.backgroundColor = Palette.surface.cgColor
        registerForDraggedTypes([.fileURL])

        orbView.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)
        orbView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 32, weight: .regular)
        orbView.contentTintColor = Palette.accent
        orbView.translatesAutoresizingMaskIntoConstraints = false
        orbView.heightAnchor.constraint(equalToConstant: 56).isActive = true

        titleLabel.font = Typography.heroTitle
        titleLabel.textColor = Palette.text
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.font = Typography.body
        subtitleLabel.textColor = Palette.textSecondary
        subtitleLabel.alignment = .center
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.maximumNumberOfLines = 2

        addFilesButton.target = self
        addFilesButton.action = #selector(handleAddFiles)
        addFolderButton.target = self
        addFolderButton.action = #selector(handleAddFolder)

        actionRow.orientation = .horizontal
        actionRow.spacing = Spacing.sm
        actionRow.translatesAutoresizingMaskIntoConstraints = false
        actionRow.addArrangedSubview(addFilesButton)
        actionRow.addArrangedSubview(addFolderButton)

        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = Spacing.md
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        stack.addArrangedSubview(orbView)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(subtitleLabel)
        stack.addArrangedSubview(actionRow)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: Spacing.xl),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Spacing.xl),
            heightAnchor.constraint(equalToConstant: 280)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func handleAddFiles() { onAddFiles?() }
    @objc private func handleAddFolder() { onAddFolder?() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        NSAnimationContext.runAnimationGroup { _ in
            layer?.borderColor = Palette.accent.cgColor
            layer?.backgroundColor = Palette.accentSoft.cgColor
        }
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        layer?.borderColor = Palette.border.cgColor
        layer?.backgroundColor = Palette.surface.cgColor
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        layer?.borderColor = Palette.border.cgColor
        layer?.backgroundColor = Palette.surface.cgColor
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
        layer?.cornerRadius = Radius.lg
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = Palette.surfaceElevated.cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = Palette.borderSubtle.cgColor

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
            thumbBg.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            thumbBg.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            thumbBg.widthAnchor.constraint(equalToConstant: 88),
            thumbBg.heightAnchor.constraint(equalToConstant: 88),
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
        didSet { updateAppearance() }
    }

    init(preset: CreatorPreset) {
        self.preset = preset
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        bezelStyle = .regularSquare
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = Radius.lg
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        titleLabel.stringValue = preset.rawValue
        titleLabel.font = Typography.cardTitle
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
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
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

        let stack = NSStackView(views: [header, blurbLabel, metrics])
        stack.orientation = .vertical
        stack.spacing = 6
        stack.alignment = .width
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14)
        ])

        updateAppearance()
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
        super.mouseDown(with: event)
        updateAppearance()
    }
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

// MARK: - Studio View Controller

private final class StudioViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let tableContainer = NSView()
    private let tableStack = NSStackView()
    private let headerLabel = NSTextField(labelWithString: "Queue")
    private let queueSubtitle = NSTextField(labelWithString: "Files appear here as you add them.")
    private let queueMetrics = NSStackView()
    private let metricSaved = StatTile(title: "SAVED", value: "0 B", detail: "0%", valueColor: Palette.success)
    private let metricRatio = StatTile(title: "COMPRESSION", value: "0%", detail: "of original size", valueColor: Palette.accent)
    private let metricFiles = StatTile(title: "FILES", value: "0 / 0", detail: "ready to export", valueColor: Palette.text)
    private let metricTime = StatTile(title: "ESTIMATED TIME", value: "Ready", detail: "0 files / s", valueColor: Palette.warning)
    private let metricsRow = NSStackView()

    private let progressCard = GlassCard(cornerRadius: Radius.xl)
    private let progressCaption = NSTextField(labelWithString: "Ready when you are.")
    private let progressBar = NSProgressIndicator()
    private let progressActionRow = NSStackView()
    private let compressButton = PrimaryButton(title: "Optimize Queue", symbol: "play.fill")
    private let stopButton = SecondaryButton(title: "Stop", symbol: "stop.fill", tint: Palette.danger)
    private let clearButton = SecondaryButton(title: "Clear all", tint: Palette.textSecondary)
    private let exportButton = SecondaryButton(title: "Export all", symbol: "square.and.arrow.down", tint: Palette.textSecondary)

    private let dropZone = DropZoneView()
    private let queueCard = GlassCard(cornerRadius: Radius.xxl)

    private let presetsSectionTitle = NSTextField(labelWithString: "Choose your intent")
    private let presetsSubtitle = NSTextField(labelWithString: "Pick the look you want. LumaShrink does the rest.")
    private let presetsGrid = NSStackView()
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
    private let previewImageView = NSImageView()
    private let previewDetailLabel = NSTextField(wrappingLabelWithString: "")
    private let previewEmpty = NSTextField(labelWithString: "No image selected")

    private let logCard = GlassCard(cornerRadius: Radius.xl)
    private let logTitle = NSTextField(labelWithString: "Activity")
    private let logTextView = NSTextView()
    private let logScroll = NSScrollView()

    private let statusBadge = PillLabel(text: "Ready", symbol: "checkmark.circle.fill", tint: Palette.success)
    private let statusBanner = NSTextField(labelWithString: "Drop a few images to begin, or pick a creator preset below.")

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
    private let keepMetadataCheck = NSButton(checkboxWithTitle: "Keep file info (EXIF, IPTC)", target: nil, action: nil)
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
        main.addArrangedSubview(buildMetricsRow())
        main.addArrangedSubview(dropZone)
        main.addArrangedSubview(buildQueueSection())
        main.addArrangedSubview(buildPresetsSection())
        main.addArrangedSubview(buildPreviewAndProgressRow())

        dropZone.onAddFiles = { [weak self] in self?.addFiles() }
        dropZone.onAddFolder = { [weak self] in self?.addFolder() }
        dropZone.onDrop = { [weak self] urls in self?.addURLs(urls) }

        applyActivePreset()
        refreshQueueTable()
    }

    private func buildHero() -> NSView {
        let hero = NSStackView()
        hero.orientation = .horizontal
        hero.alignment = .centerY
        hero.spacing = Spacing.md
        hero.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.spacing = 4
        textStack.alignment = .leading
        textStack.translatesAutoresizingMaskIntoConstraints = false
        let greeting = makeLabel("Studio", font: Typography.captionMedium, color: Palette.textTertiary)
        let title = makeLabel("Optimize your images, beautifully.", font: NSFont.systemFont(ofSize: 26, weight: .semibold), color: Palette.text)
        let subtitle = makeLabel("Drop, choose a preset, preview, and export. Everything stays on your Mac.", font: Typography.body, color: Palette.textSecondary)
        textStack.addArrangedSubview(greeting)
        textStack.addArrangedSubview(title)
        textStack.addArrangedSubview(subtitle)

        hero.addArrangedSubview(textStack)
        hero.addArrangedSubview(NSView())
        hero.addArrangedSubview(statusBadge)
        return hero
    }

    private func buildMetricsRow() -> NSStackView {
        metricsRow.orientation = .horizontal
        metricsRow.spacing = Spacing.lg
        metricsRow.alignment = .width
        metricsRow.distribution = .fillEqually
        metricsRow.translatesAutoresizingMaskIntoConstraints = false
        metricsRow.addArrangedSubview(metricSaved)
        metricsRow.addArrangedSubview(metricRatio)
        metricsRow.addArrangedSubview(metricFiles)
        metricsRow.addArrangedSubview(metricTime)
        return metricsRow
    }

    private func buildQueueSection() -> NSView {
        queueCard.translatesAutoresizingMaskIntoConstraints = false

        headerLabel.font = Typography.sectionTitle
        headerLabel.textColor = Palette.text
        queueSubtitle.font = Typography.caption
        queueSubtitle.textColor = Palette.textSecondary
        let headerStack = NSStackView(views: [headerLabel, queueSubtitle])
        headerStack.orientation = .vertical
        headerStack.spacing = 2
        headerStack.alignment = .leading
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        let clearAllButton = SecondaryButton(title: "Clear all", tint: Palette.textTertiary)
        clearAllButton.target = self
        clearAllButton.action = #selector(clearAll)
        let headerRow = NSStackView(views: [headerStack, NSView(), clearAllButton])
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.translatesAutoresizingMaskIntoConstraints = false

        tableView.headerView = nil
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.backgroundColor = .clear
        tableView.rowHeight = 112
        tableView.intercellSpacing = NSSize(width: 0, height: 10)
        tableView.selectionHighlightStyle = .regular
        tableView.target = self
        tableView.doubleAction = #selector(revealSelected)
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
        scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true

        let inner = NSStackView(views: [headerRow, scrollView])
        inner.orientation = .vertical
        inner.spacing = Spacing.md
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

    private func buildPresetsSection() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        presetsSectionTitle.font = Typography.sectionTitle
        presetsSectionTitle.textColor = Palette.text
        presetsSubtitle.font = Typography.caption
        presetsSubtitle.textColor = Palette.textSecondary
        let headerStack = NSStackView(views: [presetsSectionTitle, presetsSubtitle])
        headerStack.orientation = .vertical
        headerStack.spacing = 2
        headerStack.alignment = .leading
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        presetsGrid.orientation = .vertical
        presetsGrid.spacing = Spacing.sm
        presetsGrid.alignment = .width
        presetsGrid.translatesAutoresizingMaskIntoConstraints = false
        var currentRow: NSStackView?
        for (index, preset) in CreatorPreset.allCases.enumerated() {
            if index % 3 == 0 {
                let row = NSStackView()
                row.orientation = .horizontal
                row.spacing = Spacing.md
                row.distribution = .fillEqually
                row.alignment = .width
                row.translatesAutoresizingMaskIntoConstraints = false
                presetsGrid.addArrangedSubview(row)
                currentRow = row
            }
            if let row = currentRow {
                let card = presetCards[preset]!
                card.target = self
                card.action = #selector(handlePresetTap(_:))
                row.addArrangedSubview(card)
            }
        }
        let stack = NSStackView(views: [headerStack, presetsGrid])
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
        formatLabel.font = Typography.cardTitle
        formatLabel.textColor = Palette.text
        formatPopup.addItems(withTitles: ["Best Quality", "Auto", "Keep original", "JPEG", "PNG", "WebP"])
        formatPopup.selectItem(at: 0)

        smallestDimLabel.font = Typography.cardTitle
        smallestDimLabel.textColor = Palette.text
        smallestDimPopup.addItems(withTitles: ["160 px", "320 px", "480 px", "640 px", "800 px"])
        smallestDimPopup.selectItem(at: 1)

        qualityMinLabel.font = Typography.cardTitle
        qualityMinLabel.textColor = Palette.text
        qualityMinPopup.addItems(withTitles: ["20", "40", "60", "80"])
        qualityMinPopup.selectItem(at: 0)

        qualityMaxLabel.font = Typography.cardTitle
        qualityMaxLabel.textColor = Palette.text
        qualityMaxPopup.addItems(withTitles: ["80", "90", "95", "100"])
        qualityMaxPopup.selectItem(at: 3)

        namingLabel.font = Typography.cardTitle
        namingLabel.textColor = Palette.text
        namingPopup.addItems(withTitles: ["Same name", "Suffix", "Overwrite"])
        namingPopup.selectItem(at: 0)

        keepMetadataCheck.state = .off
        keepMetadataCheck.font = Typography.body

        chooseOutputFolderButton.target = self
        chooseOutputFolderButton.action = #selector(chooseOutputFolder)
        outputFolderPathLabel.font = Typography.caption
        outputFolderPathLabel.textColor = Palette.textSecondary

        let formatRow = labeledRow("Output format", formatPopup)
        let dimRow = labeledRow("Smallest dimension", smallestDimPopup)
        let qualityRow = NSStackView(views: [
            labeledColumn("Min quality", qualityMinPopup),
            labeledColumn("Max quality", qualityMaxPopup)
        ])
        qualityRow.orientation = .horizontal
        qualityRow.spacing = Spacing.lg
        qualityRow.alignment = .width
        qualityRow.distribution = .fillEqually
        qualityRow.translatesAutoresizingMaskIntoConstraints = false

        let namingRow = labeledRow("Naming", namingPopup)
        let folderRow = NSStackView(views: [
            NSTextField(labelWithString: "Output folder"),
            chooseOutputFolderButton
        ])
        folderRow.orientation = .horizontal
        folderRow.alignment = .centerY
        folderRow.spacing = Spacing.md
        folderRow.translatesAutoresizingMaskIntoConstraints = false
        let folderLabelContainer = (folderRow.arrangedSubviews[0] as? NSTextField)
        folderLabelContainer?.font = Typography.cardTitle
        folderLabelContainer?.textColor = Palette.text

        let folderPathRow = NSStackView(views: [outputFolderPathLabel])
        folderPathRow.orientation = .horizontal
        folderPathRow.alignment = .centerY
        folderPathRow.translatesAutoresizingMaskIntoConstraints = false

        advancedPanel.addArrangedSubview(formatRow)
        advancedPanel.addArrangedSubview(dimRow)
        advancedPanel.addArrangedSubview(qualityRow)
        advancedPanel.addArrangedSubview(namingRow)
        advancedPanel.addArrangedSubview(folderRow)
        advancedPanel.addArrangedSubview(folderPathRow)
        advancedPanel.addArrangedSubview(keepMetadataCheck)
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
        l.font = Typography.micro
        l.textColor = Palette.textTertiary
        col.addArrangedSubview(l)
        col.addArrangedSubview(control)
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
        previewTitle.font = Typography.cardTitle
        previewTitle.textColor = Palette.text
        previewSubtitle.font = Typography.caption
        previewSubtitle.textColor = Palette.textSecondary
        let titleStack = NSStackView(views: [previewTitle, previewSubtitle])
        titleStack.orientation = .vertical
        titleStack.spacing = 2
        titleStack.alignment = .leading
        titleStack.translatesAutoresizingMaskIntoConstraints = false

        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        previewImageView.wantsLayer = true
        previewImageView.layer?.cornerRadius = Radius.md
        previewImageView.layer?.cornerCurve = .continuous
        previewImageView.layer?.backgroundColor = Palette.surfaceInset.cgColor
        previewImageView.heightAnchor.constraint(equalToConstant: 220).isActive = true

        previewEmpty.font = Typography.body
        previewEmpty.textColor = Palette.textTertiary
        previewEmpty.alignment = .center
        previewEmpty.translatesAutoresizingMaskIntoConstraints = false

        previewDetailLabel.font = Typography.caption
        previewDetailLabel.textColor = Palette.textSecondary
        previewDetailLabel.translatesAutoresizingMaskIntoConstraints = false
        previewDetailLabel.maximumNumberOfLines = 2

        let stack = NSStackView(views: [titleStack, previewImageView, previewEmpty, previewDetailLabel])
        stack.orientation = .vertical
        stack.spacing = Spacing.sm
        stack.alignment = .width
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: Spacing.lg, left: Spacing.lg, bottom: Spacing.lg, right: Spacing.lg)
        previewCard.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: previewCard.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: previewCard.trailingAnchor),
            stack.topAnchor.constraint(equalTo: previewCard.topAnchor),
            stack.bottomAnchor.constraint(equalTo: previewCard.bottomAnchor)
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

    // MARK: - Preset Actions

    @objc private func handlePresetTap(_ sender: PresetCardView) {
        activePreset = sender.preset
        applyActivePreset()
        refreshQueueTable()
    }

    private func applyActivePreset() {
        for (preset, card) in presetCards {
            card.isSelectedPreset = (preset == activePreset)
        }
        settings.maxSize = activePreset.targetSize
        updateMetrics()
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
            if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
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
    }

    @objc func revealSelected() {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard row >= 0, row < queue.count else { return }
        NSWorkspace.shared.activateFileViewerSelecting([queue[row].url])
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
        if settings.outputFolder == nil && namingPopup.titleOfSelectedItem == "Same name" {
            chooseOutputFolder()
        }
        settings.maxSize = activePreset.targetSize
        let dimTitle = smallestDimPopup.titleOfSelectedItem ?? "320 px"
        settings.minSide = Int(dimTitle.replacingOccurrences(of: " px", with: "")) ?? 320
        settings.minQuality = Int(qualityMinPopup.titleOfSelectedItem ?? "20") ?? 20
        settings.maxQuality = Int(qualityMaxPopup.titleOfSelectedItem ?? "100") ?? 100
        let fmtTitle = formatPopup.titleOfSelectedItem ?? "Best Quality"
        let formatMap = ["Best Quality": "best_quality", "Auto": "auto", "Keep original": "keep", "JPEG": "jpeg", "PNG": "png", "WebP": "webp"]
        settings.outputFormat = formatMap[fmtTitle] ?? "best_quality"
        settings.isBestQuality = (settings.outputFormat == "best_quality")
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
        guard let resourceURL = Bundle.main.resourceURL,
              let runtime = URL(string: "\(resourceURL.path)/runtime") else {
            return CompressionRunResult(lines: ["[ERROR] Missing runtime."], hadError: true, bestEffort: false, outputPath: nil)
        }
        let script = runtime.appendingPathComponent("compress_image.py")
        let python = runtime.appendingPathComponent(".venv/bin/python3").path
        let pythonPath = FileManager.default.fileExists(atPath: python) ? python : "/usr/bin/python3"
        let outputDir = settings.outputFolder ?? file.url.deletingLastPathComponent()
        let args: [String]
        if settings.nameMode != "overwrite" {
            args = [script.path, file.url.path, outputDir.path, "-s", settings.maxSize, "--format", settings.isBestQuality ? "webp" : settings.outputFormat, "--name-mode", settings.nameMode, "--min-quality", String(settings.minQuality), "--max-quality", String(settings.maxQuality), "--min-side", String(settings.minSide), "--background", "FFFFFF"]
        } else {
            args = [script.path, file.url.path, "-s", settings.maxSize, "--format", settings.isBestQuality ? "webp" : settings.outputFormat, "--name-mode", settings.nameMode, "--min-quality", String(settings.minQuality), "--max-quality", String(settings.maxQuality), "--min-side", String(settings.minSide), "--background", "FFFFFF"]
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
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
        let lines = stdout.split(separator: "\n").map(String.init)
        var outputPath: URL? = nil
        for line in lines {
            if line.contains("->") && (line.contains(".webp") || line.contains(".jpg") || line.contains(".png")) {
                let parts = line.components(separatedBy: "->")
                if let last = parts.last {
                    let cleaned = last.trimmingCharacters(in: .whitespaces)
                    if let url = URL(string: cleaned), FileManager.default.fileExists(atPath: url.path) {
                        outputPath = url
                    }
                }
            }
        }
        let isError = lines.contains(where: { $0.contains("[ERROR]") })
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
        } else {
            statusBanner.stringValue = failed > 0 ? "\(failed) file\(failed == 1 ? "" : "s") had issues." : "Nothing to export."
            statusBadge.setText(failed > 0 ? "Needs attention" : "Ready")
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
            metricTime.setDetail(String(format: "%.1f files / s", rate))
        } else {
            metricTime.setValue("Ready")
            metricTime.setDetail("\(queue.count) files in queue")
        }
    }

    private func updatePreview(for file: QueueFile) {
        previewTitle.stringValue = file.url.lastPathComponent
        if file.thumbnail != nil {
            previewImageView.image = file.thumbnail
            previewEmpty.isHidden = true
        } else {
            previewImageView.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
            previewEmpty.isHidden = false
        }
        if let output = file.actualOutputSize {
            previewSubtitle.stringValue = "Compressed result ready"
            previewDetailLabel.stringValue = "\(humanSize(file.sourceSize)) → \(humanSize(output)) · \(savingPercent(source: file.sourceSize, output: output))% saved"
        } else if let estimate = file.estimatedOutputSize {
            previewSubtitle.stringValue = "Estimated output"
            previewDetailLabel.stringValue = "\(humanSize(file.sourceSize)) → ~\(humanSize(estimate))"
        } else {
            previewSubtitle.stringValue = "Source preview"
            previewDetailLabel.stringValue = "\(humanSize(file.sourceSize))"
        }
    }

    private func savingPercent(source: Int64, output: Int64) -> Int {
        guard source > 0 else { return 0 }
        return max(0, min(100, Int(round((1 - Double(output) / Double(source)) * 100))))
    }

    // MARK: - Log

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
        logTextView.textStorage?.append(attr)
    }

    // MARK: - Diagnostics

    func startupDiagnosticsReport() -> String? {
        guard let resourceURL = Bundle.main.resourceURL,
              let runtime = URL(string: "\(resourceURL.path)/runtime") else { return "Runtime missing" }
        let script = runtime.appendingPathComponent("compress_image.py").path
        let venv = runtime.appendingPathComponent(".venv/bin/python3").path
        let hasScript = FileManager.default.fileExists(atPath: script)
        let hasVenv = FileManager.default.fileExists(atPath: venv)
        return hasScript ? (hasVenv ? "Runtime ready" : "Python venv missing") : "compress_image.py missing"
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

        // Settings card
        let settingsCard = GlassCard(cornerRadius: Radius.xl)
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
        let queueCard = GlassCard(cornerRadius: Radius.xxl)
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
    }

    @objc func clearAll() {
        files.removeAll()
        refresh()
        statusBadge.setText("Ready")
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
        NSSound.beep()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { files.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTextField(labelWithString: files[row].lastPathComponent)
        cell.font = Typography.body
        cell.textColor = Palette.text
        return cell
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
        guard let resourceURL = Bundle.main.resourceURL,
              let runtime = URL(string: "\(resourceURL.path)/runtime") else {
            appendLog("[ERROR] Missing runtime")
            markFailed(at: index)
            return
        }
        let script = runtime.appendingPathComponent("compress_video.py")
        let python = runtime.appendingPathComponent(".venv/bin/python3").path
        let pythonPath = FileManager.default.fileExists(atPath: python) ? python : "/usr/bin/python3"
        let targetBytes = parseSize(activeTarget) ?? 20 * 1024 * 1024
        let outDir = outputFolder ?? file.url.deletingLastPathComponent()
        let outPath = outDir.appendingPathComponent(file.url.deletingPathExtension().lastPathComponent + "_compressed.mp4")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.currentDirectoryURL = runtime
        process.arguments = [
            script.path, file.url.path, outPath.path,
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

private final class SidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    enum Section: Int, CaseIterable {
        case studio = 0
        case utilities = 1
    }

    enum Item: Hashable {
        case section(Section)
        case studioStudio
        case studioVideo
        case studioRename
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
                return Item.studioStudio
            case .utilities:
                return index == 0 ? Item.studioVideo : Item.studioRename
            }
        }
        return Item.studioStudio
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return item is Section
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: "")
        label.font = Typography.bodyMedium
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
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
                label.stringValue = "Studio"
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
            switch leaf {
            case .studioStudio:
                label.stringValue = "Optimize"
                icon.image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: nil)
                icon.contentTintColor = Palette.accent
            case .studioVideo:
                label.stringValue = "Compress videos"
                icon.image = NSImage(systemSymbolName: "film.stack", accessibilityDescription: nil)
                icon.contentTintColor = Palette.accent
            case .studioRename:
                label.stringValue = "Rename"
                icon.image = NSImage(systemSymbolName: "character.cursor.ibeam", accessibilityDescription: nil)
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

    func selectItem(_ item: Item) {
        outline.deselectAll(nil)
        let row = outline.row(forItem: item)
        if row >= 0 { outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
    }
}

// MARK: - Split Controller
private final class AppSplitViewController: NSSplitViewController {
    let studio = StudioViewController()
    let video = VideoCompressViewController()
    let rename = RenameViewController()
    let sidebar: SidebarViewController

    init() {
        self.sidebar = SidebarViewController(onSelect: { _ in })
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()

        addSplitViewItem(NSSplitViewItem(sidebarWithViewController: sidebar))

        let tabView = NSTabView()
        tabView.autoresizingMask = [.width, .height]
        tabView.tabViewType = .noTabsNoBorder
        tabView.drawsBackground = false

        for (i, vc) in [studio, video, rename].enumerated() {
            let tab = NSTabViewItem(viewController: vc)
            tab.label = ["Optimize", "Compress Videos", "Rename"][i]
            tabView.addTabViewItem(tab)
        }
        tabView.selectTabViewItem(at: 0)

        let wrapper = NSViewController()
        wrapper.view = tabView

        let detailItem = NSSplitViewItem(viewController: wrapper)
        detailItem.minimumThickness = 800
        addSplitViewItem(detailItem)

        sidebar.onSelect = { item in
            let index: Int
            switch item {
            case .studioStudio: index = 0
            case .studioVideo: index = 1
            case .studioRename: index = 2
            case .section: return
            }
            guard tabView.tabViewItems.indices.contains(index) else { return }
            tabView.selectTabViewItem(at: index)
        }
        sidebar.selectItem(.studioStudio)
    }
}

// MARK: - App Delegate

final class ImageCompressorAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var split: AppSplitViewController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        split = AppSplitViewController()

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let windowWidth = min(1360, max(1040, screenFrame.width * 0.92))
        let windowHeight = min(900, max(640, screenFrame.height))

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "LumaShrink"
        window.contentMinSize = NSSize(width: 1080, height: 720)
        window.minSize = NSSize(width: 1080, height: 720)
        window.isRestorable = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
        window.backgroundColor = Palette.window
        window.isOpaque = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.center()
        window.isReleasedWhenClosed = false
        window.contentViewController = split
        configureMainMenu()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func configureMainMenu() {
        let main = NSMenu()

        // ── LumaShrink ──
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(title: "LumaShrink"); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About LumaShrink", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        addMenu("Preferences…", to: appMenu, key: ",", target: nil, action: nil)
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
        fileMenu.addItem(withTitle: "New Queue", action: nil, keyEquivalent: "n")
        fileMenu.addItem(.separator())
        addMenu("Add Images…", to: fileMenu, key: "o", target: split.studio, action: #selector(StudioViewController.addFiles))
        addMenu("Add Folder…", to: fileMenu, key: "o", modifiers: [.command, .shift], target: split.studio, action: #selector(StudioViewController.addFolder))
        addMenu("Add Videos…", to: fileMenu, key: "v", modifiers: [.command, .shift], target: split.video, action: #selector(VideoCompressViewController.chooseFiles))
        fileMenu.addItem(.separator())
        addMenu("Choose Output Folder…", to: fileMenu, key: "s", target: split.studio, action: #selector(StudioViewController.chooseOutputFolder))
        addMenu("Open Output Folder", to: fileMenu, key: ".", target: split.studio, action: #selector(StudioViewController.openOutputFolder))
        fileMenu.addItem(.separator())
        addMenu("Choose Files for Rename…", to: fileMenu, key: "r", modifiers: [.command, .shift], target: split.rename, action: #selector(RenameViewController.chooseFiles))
        fileMenu.addItem(.separator())
        addMenu("Reload Session", to: fileMenu, key: "r", target: nil, action: nil)
        fileMenu.addItem(.separator())
        addMenu("Close Window", to: fileMenu, key: "w", target: nil, action: #selector(NSWindow.performClose(_:)))

        // ── Actions ──
        let actionItem = NSMenuItem(); main.addItem(actionItem)
        let actionMenu = NSMenu(title: "Actions"); actionItem.submenu = actionMenu
        addMenu("Compress Now", to: actionMenu, key: "\r", target: split.studio, action: #selector(StudioViewController.startCompression))
        addMenu("Clear Queue", to: actionMenu, key: "\u{8}", modifiers: [.command, .shift], target: split.studio, action: #selector(StudioViewController.clearAll))
        actionMenu.addItem(.separator())
        addMenu("Choose Extension Files…", to: actionMenu, key: "e", modifiers: [.command, .shift], target: split.rename, action: #selector(RenameViewController.chooseFiles))
        addMenu("Change Extension", to: actionMenu, key: "e", target: split.rename, action: #selector(RenameViewController.applyRename))

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
        helpMenu.addItem(withTitle: "LumaShrink Help", action: nil, keyEquivalent: "")
        helpMenu.addItem(.separator())

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
