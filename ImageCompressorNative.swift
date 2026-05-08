import AppKit
import UserNotifications

private func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

private enum Palette {
    static let window = NSColor(calibratedRed: 0.07, green: 0.07, blue: 0.08, alpha: 1.0)
    static let windowTop = NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.13, alpha: 1.0)
    static let card = NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.16, alpha: 0.9)
    static let cardAlt = NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.20, alpha: 0.92)
    static let border = NSColor.white.withAlphaComponent(0.12)
    static let accent = NSColor(calibratedRed: 0.43, green: 0.79, blue: 0.98, alpha: 1.0)
    static let accentSoft = NSColor(calibratedRed: 0.19, green: 0.30, blue: 0.40, alpha: 1.0)
    static let accentBright = NSColor(calibratedRed: 0.62, green: 0.87, blue: 1.00, alpha: 1.0)
    static let primaryButton = NSColor(calibratedRed: 0.33, green: 0.67, blue: 0.90, alpha: 1.0)
    static let primaryButtonPressed = NSColor(calibratedRed: 0.25, green: 0.56, blue: 0.78, alpha: 1.0)
    static let secondaryButton = NSColor(calibratedRed: 0.20, green: 0.22, blue: 0.25, alpha: 1.0)
    static let secondaryButtonText = NSColor(calibratedRed: 0.93, green: 0.95, blue: 0.98, alpha: 1.0)
    static let dangerButton = NSColor(calibratedRed: 0.42, green: 0.19, blue: 0.22, alpha: 1.0)
    static let heroStart = NSColor(calibratedRed: 0.16, green: 0.22, blue: 0.30, alpha: 1.0)
    static let heroEnd = NSColor(calibratedRed: 0.14, green: 0.18, blue: 0.24, alpha: 1.0)
    static let text = NSColor(calibratedRed: 0.92, green: 0.94, blue: 0.97, alpha: 1.0)
    static let muted = NSColor(calibratedRed: 0.72, green: 0.76, blue: 0.82, alpha: 1.0)
    static let subtle = NSColor(calibratedRed: 0.75, green: 0.69, blue: 0.52, alpha: 1.0)
    static let warning = NSColor(calibratedRed: 0.93, green: 0.72, blue: 0.34, alpha: 1.0)
    static let success = NSColor(calibratedRed: 0.43, green: 0.84, blue: 0.62, alpha: 1.0)
    static let danger = NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.58, alpha: 1.0)
    static let log = NSColor(calibratedRed: 0.11, green: 0.12, blue: 0.14, alpha: 1.0)
    static let pill = NSColor(calibratedRed: 0.20, green: 0.22, blue: 0.25, alpha: 1.0)
    static let overlay = NSColor(calibratedRed: 0.15, green: 0.16, blue: 0.19, alpha: 1.0)
    static let rose = NSColor(calibratedRed: 0.66, green: 0.32, blue: 0.41, alpha: 1.0)
    static let cyan = NSColor(calibratedRed: 0.38, green: 0.75, blue: 0.90, alpha: 1.0)
    static let mint = NSColor(calibratedRed: 0.40, green: 0.78, blue: 0.66, alpha: 1.0)
    static let champagne = NSColor(calibratedRed: 0.93, green: 0.72, blue: 0.34, alpha: 1.0)
}

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

        guard let handle = try? FileHandle(forWritingTo: logURL) else {
            return
        }

        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }

    private func cleanupOldLogs(keepDays: Int) {
        guard let logDir = logURL.deletingLastPathComponent() as URL? else { return }
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: logDir,
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

private class CardView: NSVisualEffectView {
    private let innerHighlightLayer = CALayer()
    private let topSheenLayer = CAGradientLayer()

    init(background: NSColor = Palette.card) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        material = .underWindowBackground
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.backgroundColor = background.cgColor
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.borderColor = Palette.border.cgColor
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.05).cgColor
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        layer?.shadowOpacity = 1
        layer?.shadowRadius = 8

        innerHighlightLayer.borderWidth = 1
        innerHighlightLayer.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        innerHighlightLayer.cornerCurve = .continuous
        layer?.addSublayer(innerHighlightLayer)

        topSheenLayer.colors = [
            NSColor.white.withAlphaComponent(0.06).cgColor,
            NSColor.white.withAlphaComponent(0.01).cgColor,
            NSColor.clear.cgColor,
        ]
        topSheenLayer.locations = [0, 0.34, 1]
        topSheenLayer.startPoint = CGPoint(x: 0.15, y: 1)
        topSheenLayer.endPoint = CGPoint(x: 1, y: 0)
        topSheenLayer.cornerCurve = .continuous
        layer?.addSublayer(topSheenLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let radius = layer?.cornerRadius ?? 28
        innerHighlightLayer.frame = bounds.insetBy(dx: 2, dy: 2)
        innerHighlightLayer.cornerRadius = max(radius - 2, 0)
        topSheenLayer.frame = bounds
        topSheenLayer.cornerRadius = radius
    }
}

private final class GradientBackgroundView: NSView {
    private let gradientLayer = CAGradientLayer()
    private let glowTopRight = CALayer()
    private let glowBottomLeft = CALayer()
    private let glowCenter = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        gradientLayer.colors = [Palette.windowTop.cgColor, Palette.window.cgColor]
        gradientLayer.startPoint = CGPoint(x: 0.05, y: 1.0)
        gradientLayer.endPoint = CGPoint(x: 0.95, y: 0.0)

        layer?.addSublayer(gradientLayer)

        [glowTopRight, glowBottomLeft, glowCenter].forEach { glow in
            glow.opacity = 1
            glow.shadowOpacity = 1
            glow.shadowRadius = 60
            glow.shadowOffset = .zero
            layer?.addSublayer(glow)
        }

        glowTopRight.backgroundColor = Palette.accentSoft.withAlphaComponent(0.12).cgColor
        glowTopRight.shadowColor = Palette.accentSoft.withAlphaComponent(0.2).cgColor

        glowBottomLeft.backgroundColor = Palette.mint.withAlphaComponent(0.10).cgColor
        glowBottomLeft.shadowColor = Palette.mint.withAlphaComponent(0.2).cgColor

        glowCenter.backgroundColor = Palette.cyan.withAlphaComponent(0.08).cgColor
        glowCenter.shadowColor = Palette.cyan.withAlphaComponent(0.2).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        gradientLayer.frame = bounds

        glowTopRight.frame = CGRect(x: bounds.maxX - 380, y: bounds.maxY - 320, width: 220, height: 220)
        glowBottomLeft.frame = CGRect(x: 64, y: 120, width: 180, height: 180)
        glowCenter.frame = CGRect(x: bounds.midX - 80, y: bounds.midY - 90, width: 160, height: 160)

        [glowTopRight, glowBottomLeft, glowCenter].forEach { glow in
            glow.cornerRadius = glow.bounds.width / 2
        }
    }
}

private final class GradientCardView: CardView {
    private let gradientLayer = CAGradientLayer()

    init(colors: [NSColor]) {
        super.init(background: .clear)
        material = .sidebar
        gradientLayer.colors = colors.map(\.cgColor)
        gradientLayer.startPoint = CGPoint(x: 0, y: 1)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0)
        layer?.insertSublayer(gradientLayer, at: 0)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        gradientLayer.frame = bounds
        gradientLayer.cornerRadius = layer?.cornerRadius ?? 22
    }
}

private final class StyledTextField: NSTextField {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    convenience init(value: String) {
        self.init(frame: .zero)
        stringValue = value
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func commonInit() {
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        drawsBackground = true
        backgroundColor = Palette.pill
        textColor = Palette.text
        font = premiumFont(size: 14, weight: .semibold)
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = 20
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.22).cgColor
        layer?.shadowOpacity = 1
        layer?.shadowOffset = CGSize(width: 0, height: -6)
        layer?.shadowRadius = 12
        cell?.backgroundStyle = .emphasized
        heightAnchor.constraint(equalToConstant: 46).isActive = true
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class DropZoneView: NSView {
    var onDrop: (([URL]) -> Void)?

    private let iconView = NSImageView()
    private let titleLabel = makeLabel(
        "Drop images here",
        size: 24,
        weight: .semibold,
        color: Palette.text
    )
    private let subtitleLabel = makeWrappingLabel(
        "Drag JPG, PNG, WebP, TIFF, or entire folders into this area.",
        size: 13,
        weight: .regular,
        color: Palette.muted
    )

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = Palette.cardAlt.cgColor
        layer?.cornerRadius = 26
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 2
        layer?.borderColor = Palette.accentBright.withAlphaComponent(0.34).cgColor
        registerForDraggedTypes([.fileURL])
        setAccessibilityLabel("Image drop zone")
        setAccessibilityHelp("Drop image files or folders here to add them to the compression queue.")

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        addSubview(stack)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = makeSymbolImage("square.and.arrow.down.on.square.fill", pointSize: 38)
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 38, weight: .semibold)
        iconView.contentTintColor = Palette.accentBright
        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
            heightAnchor.constraint(equalToConstant: 154)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        layer?.borderColor = Palette.accentBright.cgColor
        layer?.backgroundColor = Palette.accentSoft.withAlphaComponent(0.44).cgColor
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        layer?.borderColor = Palette.accentBright.withAlphaComponent(0.34).cgColor
        layer?.backgroundColor = Palette.cardAlt.cgColor
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        draggingExited(nil)
        guard
            let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]),
            let urls = items as? [URL]
        else {
            return false
        }

        onDrop?(urls)
        return !urls.isEmpty
    }
}

private final class ExtensionDropZoneView: NSView {
    var onDrop: (([URL]) -> Void)?

    private let titleLabel = makeLabel(
        "Drop files here to change extensions",
        size: 16,
        weight: .semibold,
        color: Palette.text
    )
    private let subtitleLabel = makeWrappingLabel(
        "Drop one or many files, then type the new extension below.",
        size: 12,
        weight: .regular,
        color: Palette.muted
    )

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = Palette.overlay.cgColor
        layer?.cornerRadius = 22
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1.5
        layer?.borderColor = Palette.border.cgColor
        registerForDraggedTypes([.fileURL])
        setAccessibilityLabel("File extension drop zone")
        setAccessibilityHelp("Drop files here to choose them for extension changes.")

        let row = NSStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        addSubview(row)

        row.addArrangedSubview(makeSymbolBadge(symbol: "arrow.down.doc.fill", tint: Palette.mint))

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.spacing = 4
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(subtitleLabel)
        row.addArrangedSubview(textStack)
        row.addArrangedSubview(NSView())

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            heightAnchor.constraint(equalToConstant: 84)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        layer?.borderColor = Palette.mint.cgColor
        layer?.backgroundColor = Palette.mint.withAlphaComponent(0.18).cgColor
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        layer?.borderColor = Palette.border.cgColor
        layer?.backgroundColor = Palette.overlay.cgColor
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        draggingExited(nil)
        guard
            let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]),
            let urls = items as? [URL]
        else {
            return false
        }

        onDrop?(urls)
        return !urls.isEmpty
    }
}

private final class VideoDropZoneView: NSView {
    var onDrop: (([URL]) -> Void)?

    private let titleLabel = makeLabel(
        "Drop videos here",
        size: 16,
        weight: .semibold,
        color: Palette.text
    )
    private let subtitleLabel = makeWrappingLabel(
        "Drop one or many videos, then compress them from the video block.",
        size: 12,
        weight: .regular,
        color: Palette.muted
    )

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = Palette.overlay.cgColor
        layer?.cornerRadius = 22
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1.5
        layer?.borderColor = Palette.border.cgColor
        registerForDraggedTypes([.fileURL])
        setAccessibilityLabel("Video drop zone")
        setAccessibilityHelp("Drop one or more videos here to choose them for compression.")

        let row = NSStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        addSubview(row)

        row.addArrangedSubview(makeSymbolBadge(symbol: "video.fill.badge.plus", tint: Palette.rose))

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.spacing = 4
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(subtitleLabel)
        row.addArrangedSubview(textStack)
        row.addArrangedSubview(NSView())

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            heightAnchor.constraint(equalToConstant: 84)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        layer?.borderColor = Palette.rose.cgColor
        layer?.backgroundColor = Palette.rose.withAlphaComponent(0.18).cgColor
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        layer?.borderColor = Palette.border.cgColor
        layer?.backgroundColor = Palette.overlay.cgColor
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        draggingExited(nil)
        guard
            let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]),
            let urls = items as? [URL]
        else {
            return false
        }

        onDrop?(urls)
        return !urls.isEmpty
    }
}

private struct CompressionSettings {
    let maxSize: String
    let outputFormat: String
    let nameMode: String
    let outputFolder: URL?
}

private struct CompressionRunResult {
    let lines: [String]
    let hadError: Bool
    let bestEffort: Bool
}

private enum QueueFileStatus: String {
    case queued = "Queued"
    case processing = "Processing"
    case done = "Done"
    case bestEffort = "Best Effort"
    case skipped = "Skipped"
    case failed = "Failed"
}

private struct QueueFileState {
    var status: QueueFileStatus = .queued
}

private struct PreviewCacheEntry {
    let imageData: Data
    let outputText: String
    let status: String
}

final class ImageCompressorAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var controller: AppViewController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = AppViewController()
        self.controller = controller

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let windowWidth = min(1360, max(1040, screenFrame.width * 0.92))
        let windowHeight = min(900, max(640, screenFrame.height))

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Image Compressor"
        window.contentMinSize = NSSize(width: 980, height: 700)
        window.contentMaxSize = NSSize(width: 1440, height: 900)
        window.minSize = NSSize(width: 860, height: 640)
        window.maxSize = NSSize(width: min(1440, screenFrame.width), height: min(900, screenFrame.height))
        window.isRestorable = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
        window.backgroundColor = .clear
        window.isOpaque = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.center()
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        configureMainMenu(for: controller)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        AppLogger.shared.write("Native app launched successfully.")
        if let report = controller.startupDiagnosticsReport() {
            AppLogger.shared.write(report)
            controller.setStartupStatus(report)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func configureMainMenu(for controller: AppViewController) {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu(title: "Image Compressor")
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "About Image Compressor", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Image Compressor", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Image Compressor", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu
        addMenuItem("Add Images...", to: fileMenu, action: #selector(AppViewController.addFiles), key: "o", target: controller)
        addMenuItem("Add Folder...", to: fileMenu, action: #selector(AppViewController.addFolder), key: "o", modifiers: [.command, .shift], target: controller)
        fileMenu.addItem(.separator())
        addMenuItem("Choose Output Folder...", to: fileMenu, action: #selector(AppViewController.chooseOutputFolder), key: "s", target: controller)
        addMenuItem("Open Output Folder", to: fileMenu, action: #selector(AppViewController.openOutputFolder), key: ".", target: controller)
        addMenuItem("Reload Session", to: fileMenu, action: #selector(AppViewController.reloadSession), key: "r", target: controller)
        fileMenu.addItem(.separator())
        addMenuItem("Close Window", to: fileMenu, action: #selector(NSWindow.performClose(_:)), key: "w", target: nil)

        let actionMenuItem = NSMenuItem()
        mainMenu.addItem(actionMenuItem)
        let actionMenu = NSMenu(title: "Actions")
        actionMenuItem.submenu = actionMenu
        addMenuItem("Compress Now", to: actionMenu, action: #selector(AppViewController.startCompression), key: "\r", target: controller)
        addMenuItem("Clear Queue", to: actionMenu, action: #selector(AppViewController.clearAll), key: "\u{8}", modifiers: [.command, .shift], target: controller)
        actionMenu.addItem(.separator())
        addMenuItem("Choose Extension Files...", to: actionMenu, action: #selector(AppViewController.chooseExtensionFile), key: "e", modifiers: [.command, .shift], target: controller)
        addMenuItem("Change Extension", to: actionMenu, action: #selector(AppViewController.applyExtensionChange), key: "e", target: controller)

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    private func addMenuItem(
        _ title: String,
        to menu: NSMenu,
        action: Selector,
        key: String,
        modifiers: NSEvent.ModifierFlags = [.command],
        target: AnyObject?
    ) {
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

private final class AppViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let logger = AppLogger.shared
    private let sessionStateKey = "image_compressor_session_v1"
    private let supportedExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "bmp", "tif", "tiff"]

    private var selectedFiles: [URL] = []
    private var fileStates: [String: QueueFileState] = [:]
    private var previewCache: [String: PreviewCacheEntry] = [:]
    private var compressionRunStartedAt: Date?
    private var lastOutputFolder: URL?
    private var isRunning = false
    private var previewWorkItem: DispatchWorkItem?
    private var previewRequestID = UUID()
    private var previewCard: NSView?
    private var previewHeightConstraint: NSLayoutConstraint?
    private var extensionToolFileURLs: [URL] = []
    private let batchUILock = NSLock()
    private var pendingBatchLogLines: [String] = []
    private var pendingBatchCompleted = 0
    private var isBatchUIFlushScheduled = false
    private let compressionProcessLock = NSLock()
    private var activeCompressionProcesses: [Process] = []
    private var stopRequested = false

    private let queuedValueLabel = makeLabel("0 files", size: 24, weight: .semibold, color: Palette.text)
    private let queuedDetailLabel = makeLabel("0 B total", size: 12, weight: .regular, color: Palette.muted)
    private let targetValueLabel = makeLabel("150 KB max", size: 24, weight: .semibold, color: Palette.text)
    private let targetDetailLabel = makeLabel("Fast WebP target", size: 12, weight: .regular, color: Palette.muted)
    private let outputValueLabel = makeLabel("Same Name", size: 24, weight: .semibold, color: Palette.text)
    private let outputDetailLabel = makeLabel("best extension", size: 12, weight: .regular, color: Palette.muted)

    private let queueHintLabel = makeWrappingLabel(
        "Nothing is queued yet. Add files, add a folder, or drag images into the drop zone.",
        size: 12,
        weight: .regular,
        color: Palette.muted
    )
    private let saveModeHintLabel = makeWrappingLabel(
        "Fast mode chooses the best output format and targets 150 KB.",
        size: 12,
        weight: .regular,
        color: Palette.warning
    )
    private let statusLabel = makeWrappingLabel(
        "Everything runs locally on your Mac. Add files and press Compress Now.",
        size: 13,
        weight: .semibold,
        color: Palette.text
    )

    private let tableView = NSTableView()
    private let logTextView = NSTextView()
    private let progressIndicator = NSProgressIndicator()
    private let batchProgressIndicator = NSProgressIndicator()
    private let batchProgressLabel = makeLabel("0 complete / 0 left", size: 12, weight: .medium, color: Palette.muted)

    private let maxSizeField = StyledTextField(value: "150kb")
    private let qualitySlider = NSSlider(value: 85, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let qualityValueLabel = makeLabel("85%", size: 14, weight: .medium, color: Palette.text)
    private let previewToggleButton = NSButton(title: "Show Live Preview", target: nil, action: nil)
    private let formatPopup = NSPopUpButton()
    private let saveModePopup = NSPopUpButton()
    private let outputFolderField = StyledTextField(value: "")
    private let targetPresetControl = NSSegmentedControl(labels: ["WhatsApp", "Email", "Web", "Archive"], trackingMode: .selectOne, target: nil, action: nil)
    private let previewOriginalImageView = NSImageView()
    private let previewOutputImageView = NSImageView()
    private let previewOriginalLabel = makeLabel("Original", size: 12, weight: .semibold, color: Palette.muted)
    private let previewOutputLabel = makeLabel("Move the slider", size: 12, weight: .semibold, color: Palette.muted)
    private let previewStatusLabel = makeWrappingLabel(
        "Add an image to see a live quality preview.",
        size: 12,
        weight: .regular,
        color: Palette.muted
    )

    private let addFilesButton = NSButton(title: "Add Files", target: nil, action: nil)
    private let addFolderButton = NSButton(title: "Add Folder", target: nil, action: nil)
    private let removeSelectedButton = NSButton(title: "Remove Selected", target: nil, action: nil)
    private let clearAllButton = NSButton(title: "Clear All", target: nil, action: nil)
    private let chooseOutputButton = NSButton(title: "Choose", target: nil, action: nil)
    private let clearOutputButton = NSButton(title: "Clear", target: nil, action: nil)
    private let openOutputButton = NSButton(title: "Open Output Folder", target: nil, action: nil)
    private let stopButton = NSButton(title: "Stop", target: nil, action: nil)
    private let compressButton = NSButton(title: "Compress Now", target: nil, action: nil)
    private let chooseExtensionFileButton = NSButton(title: "Choose Files", target: nil, action: nil)
    private let applyExtensionButton = NSButton(title: "Change Extension", target: nil, action: nil)
    private let extensionFileField = StyledTextField(value: "No file selected")
    private let extensionPopup = NSPopUpButton()
    private let extensionToolStatusLabel = makeWrappingLabel(
        "Pick one or more files, type the new extension, then rename them in the same folder.",
        size: 12,
        weight: .regular,
        color: Palette.muted
    )
    private var videoFileURLs: [URL] = []
    private let chooseVideoButton = NSButton(title: "Choose Video", target: nil, action: nil)
    private let compressVideoButton = NSButton(title: "Compress Video", target: nil, action: nil)
    private let videoFileField = StyledTextField(value: "No video selected")
    private let videoTargetField = StyledTextField(value: "auto")
    private let videoStatusLabel = makeWrappingLabel(
        "Choose a video around 10 MB or less. Quality 18 tries first, then 20/21 if needed.",
        size: 12,
        weight: .regular,
        color: Palette.muted
    )
    private weak var contentScrollView: NSScrollView?
    private var controlsRowStack: NSStackView?
    private var bottomRowStack: NSStackView?

    override func loadView() {
        view = GradientBackgroundView()
        view.appearance = NSAppearance(named: .darkAqua)

        let shell = NSStackView()
        shell.translatesAutoresizingMaskIntoConstraints = false
        shell.orientation = .vertical
        shell.spacing = 20
        view.addSubview(shell)

        NSLayoutConstraint.activate([
            shell.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22),
            shell.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -22),
            shell.topAnchor.constraint(equalTo: view.topAnchor, constant: 18),
            shell.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -18)
        ])

        let topBar = buildTopBarCard()
        topBar.heightAnchor.constraint(equalToConstant: 82).isActive = true
        shell.addArrangedSubview(topBar)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        contentScrollView = scrollView
        shell.addArrangedSubview(scrollView)

        let documentView = FlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView

        let root = NSStackView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.orientation = .vertical
        root.spacing = 22
        documentView.addSubview(root)

        NSLayoutConstraint.activate([
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            root.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: documentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            root.widthAnchor.constraint(equalTo: documentView.widthAnchor),
        ])

        let statRow = NSStackView(views: [
            buildStatCard(title: "Queued", valueLabel: queuedValueLabel, detailLabel: queuedDetailLabel, symbol: "tray", tint: Palette.cyan),
            buildStatCard(title: "Target", valueLabel: targetValueLabel, detailLabel: targetDetailLabel, symbol: "target", tint: Palette.warning),
            buildStatCard(title: "Output", valueLabel: outputValueLabel, detailLabel: outputDetailLabel, symbol: "folder", tint: Palette.mint),
        ])
        statRow.orientation = .horizontal
        statRow.spacing = 14
        statRow.distribution = .fillEqually
        statRow.heightAnchor.constraint(equalToConstant: 128).isActive = true
        root.addArrangedSubview(statRow)

        let controlsRow = NSStackView(views: [buildSourcesCard(), buildSettingsCard()])
        controlsRow.orientation = .horizontal
        controlsRow.spacing = 18
        controlsRow.distribution = .fillEqually
        controlsRow.heightAnchor.constraint(equalToConstant: 340).isActive = true
        controlsRowStack = controlsRow
        root.addArrangedSubview(controlsRow)

        let extensionToolCard = buildExtensionToolCard()
        extensionToolCard.heightAnchor.constraint(equalToConstant: 310).isActive = true
        root.addArrangedSubview(extensionToolCard)

        let videoCompressionCard = buildVideoCompressionCard()
        videoCompressionCard.heightAnchor.constraint(equalToConstant: 400).isActive = true
        root.addArrangedSubview(videoCompressionCard)

        let previewCard = buildPreviewCard()
        let previewHeightConstraint = previewCard.heightAnchor.constraint(equalToConstant: 330)
        previewHeightConstraint.isActive = true
        self.previewCard = previewCard
        self.previewHeightConstraint = previewHeightConstraint
        root.addArrangedSubview(previewCard)

        let bottomRow = NSStackView(views: [buildQueueCard(), buildLogCard()])
        bottomRow.orientation = .horizontal
        bottomRow.spacing = 18
        bottomRow.distribution = .fillEqually
        bottomRow.setHuggingPriority(.defaultLow, for: .vertical)
        bottomRowStack = bottomRow
        root.addArrangedSubview(bottomRow)

        let footer = buildFooterCard()
        footer.heightAnchor.constraint(equalToConstant: 72).isActive = true
        shell.addArrangedSubview(footer)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureControls()
        refreshQueue()
        appendLog("Ready. Add files or folders to begin.")
        promptAndRestoreSessionState()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        DispatchQueue.main.async { [weak self] in
            if let scrollView = self?.contentScrollView {
                scrollView.contentView.scroll(to: .zero)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }
    }

    private func configureControls() {
        [addFilesButton, addFolderButton, removeSelectedButton, clearAllButton].forEach {
            styleSecondaryButton($0)
        }
        styleSecondaryButton(chooseOutputButton)
        styleSecondaryButton(clearOutputButton)
        styleSecondaryButton(openOutputButton)
        styleSecondaryButton(previewToggleButton)
        styleSecondaryButton(chooseExtensionFileButton)
        styleSecondaryButton(chooseVideoButton)
        stylePrimaryButton(applyExtensionButton)
        stylePrimaryButton(compressButton)
        stylePrimaryButton(compressVideoButton)
        styleDangerButton(clearAllButton)
        styleDangerButton(stopButton)

        addFilesButton.target = self
        addFilesButton.action = #selector(addFiles)
        addFolderButton.target = self
        addFolderButton.action = #selector(addFolder)
        removeSelectedButton.target = self
        removeSelectedButton.action = #selector(removeSelected)
        clearAllButton.target = self
        clearAllButton.action = #selector(clearAll)
        chooseOutputButton.target = self
        chooseOutputButton.action = #selector(chooseOutputFolder)
        clearOutputButton.target = self
        clearOutputButton.action = #selector(clearOutputFolder)
        openOutputButton.target = self
        openOutputButton.action = #selector(openOutputFolder)
        stopButton.target = self
        stopButton.action = #selector(stopCompression)
        compressButton.target = self
        compressButton.action = #selector(startCompression)
        chooseExtensionFileButton.target = self
        chooseExtensionFileButton.action = #selector(chooseExtensionFile)
        applyExtensionButton.target = self
        applyExtensionButton.action = #selector(applyExtensionChange)
        chooseVideoButton.target = self
        chooseVideoButton.action = #selector(chooseVideoFile)
        compressVideoButton.target = self
        compressVideoButton.action = #selector(startVideoCompression)

        addFilesButton.setAccessibilityLabel("Add image files")
        addFilesButton.setAccessibilityHelp("Choose one or more image files to add to the compression queue.")
        addFolderButton.setAccessibilityLabel("Add image folder")
        addFolderButton.setAccessibilityHelp("Choose a folder and add supported images from it.")
        removeSelectedButton.setAccessibilityLabel("Remove selected files")
        removeSelectedButton.setAccessibilityHelp("Remove the selected items from the image queue.")
        clearAllButton.setAccessibilityLabel("Clear image queue")
        clearAllButton.setAccessibilityHelp("Remove every image from the queue.")
        chooseOutputButton.setAccessibilityLabel("Choose output folder")
        chooseOutputButton.setAccessibilityHelp("Choose where completed image or video outputs should be stored.")
        clearOutputButton.setAccessibilityLabel("Clear output folder")
        clearOutputButton.setAccessibilityHelp("Return to saving outputs beside the source files.")
        openOutputButton.setAccessibilityLabel("Open output folder")
        openOutputButton.setAccessibilityHelp("Open the folder for the most recent completed image, video, or extension action.")
        stopButton.setAccessibilityLabel("Stop compression")
        stopButton.setAccessibilityHelp("Stop the current compression run.")
        compressButton.setAccessibilityLabel("Compress images now")
        compressButton.setAccessibilityHelp("Start compressing the images currently in the queue.")
        chooseExtensionFileButton.setAccessibilityLabel("Choose files for extension change")
        chooseExtensionFileButton.setAccessibilityHelp("Choose one or more files for the extension rename tool.")
        applyExtensionButton.setAccessibilityLabel("Change selected file extensions")
        applyExtensionButton.setAccessibilityHelp("Apply the selected extension to the chosen files.")
        chooseVideoButton.setAccessibilityLabel("Choose videos")
        chooseVideoButton.setAccessibilityHelp("Choose one or more videos to compress.")
        compressVideoButton.setAccessibilityLabel("Compress selected videos")
        compressVideoButton.setAccessibilityHelp("Compress the selected videos using the high-quality video settings.")
        previewToggleButton.setAccessibilityLabel("Toggle live image preview")
        previewToggleButton.setAccessibilityHelp("Show or hide the local image quality preview.")
        maxSizeField.setAccessibilityLabel("Image target size")
        outputFolderField.setAccessibilityLabel("Output folder path")
        extensionFileField.setAccessibilityLabel("Selected files for extension change")
        extensionPopup.setAccessibilityLabel("New file extension")
        videoFileField.setAccessibilityLabel("Selected video files")
        videoTargetField.setAccessibilityLabel("Video compression target")
        targetPresetControl.setAccessibilityLabel("Image target size presets")
        formatPopup.setAccessibilityLabel("Image output format")
        saveModePopup.setAccessibilityLabel("Image save mode")

        openOutputButton.isEnabled = false
        stopButton.isEnabled = false
        applyExtensionButton.isEnabled = false
        compressVideoButton.isEnabled = false
        compressButton.keyEquivalent = "\r"

        outputFolderField.isEditable = false
        outputFolderField.textColor = Palette.muted
        extensionFileField.isEditable = false
        extensionFileField.textColor = Palette.muted
        videoFileField.isEditable = false
        videoFileField.textColor = Palette.muted

        formatPopup.addItems(withTitles: ["auto"])
        saveModePopup.addItems(withTitles: ["same-name"])
        extensionPopup.addItems(withTitles: ["webp", "jpg", "jpeg", "png", "heic", "tiff", "bmp", "gif"])
        stylePopup(formatPopup)
        stylePopup(saveModePopup)
        stylePopup(extensionPopup)
        formatPopup.selectItem(withTitle: "auto")
        formatPopup.isEnabled = false
        saveModePopup.selectItem(withTitle: "same-name")
        saveModePopup.isEnabled = false
        saveModePopup.target = self
        saveModePopup.action = #selector(saveModeChanged)
        extensionPopup.selectItem(withTitle: "webp")

        previewToggleButton.translatesAutoresizingMaskIntoConstraints = false
        previewToggleButton.setButtonType(.pushOnPushOff)
        previewToggleButton.state = .off
        previewToggleButton.target = self
        previewToggleButton.action = #selector(toggleLivePreview(_:))
        previewToggleButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
        previewToggleButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        targetPresetControl.segmentStyle = .capsule
        targetPresetControl.controlSize = .large
        targetPresetControl.translatesAutoresizingMaskIntoConstraints = false
        targetPresetControl.selectedSegment = 0
        targetPresetControl.target = self
        targetPresetControl.action = #selector(setTargetFromSegment(_:))
        targetPresetControl.heightAnchor.constraint(equalToConstant: 32).isActive = true

        qualitySlider.translatesAutoresizingMaskIntoConstraints = false
        qualitySlider.isEnabled = true
        qualitySlider.isContinuous = true
        qualitySlider.controlSize = .large
        qualitySlider.sliderType = .linear
        qualitySlider.numberOfTickMarks = 0
        qualitySlider.allowsTickMarkValuesOnly = false
        qualitySlider.target = self
        qualitySlider.action = #selector(qualitySliderChanged(_:))
        qualitySlider.sendAction(on: [.leftMouseDragged, .leftMouseUp])
        qualitySlider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        qualitySlider.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        qualitySlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true
        qualityValueLabel.alignment = .right
        qualityValueLabel.widthAnchor.constraint(equalToConstant: 48).isActive = true

        [previewOriginalImageView, previewOutputImageView].forEach { imageView in
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.wantsLayer = true
            imageView.layer?.backgroundColor = Palette.log.cgColor
            imageView.layer?.cornerRadius = 10
            imageView.layer?.borderWidth = 1
            imageView.layer?.borderColor = Palette.border.cgColor
            imageView.heightAnchor.constraint(equalToConstant: 92).isActive = true
        }

        configureButtonImage(addFilesButton, symbolName: "plus.square")
        configureButtonImage(addFolderButton, symbolName: "folder.badge.plus")
        configureButtonImage(removeSelectedButton, symbolName: "minus.square")
        configureButtonImage(clearAllButton, symbolName: "trash")
        configureButtonImage(chooseOutputButton, symbolName: "folder")
        configureButtonImage(clearOutputButton, symbolName: "xmark.circle")
        configureButtonImage(openOutputButton, symbolName: "folder")
        configureButtonImage(stopButton, symbolName: "stop.circle")
        configureButtonImage(previewToggleButton, symbolName: "eye")
        configureButtonImage(compressButton, symbolName: "arrow.down.circle")
        configureButtonImage(chooseExtensionFileButton, symbolName: "doc")
        configureButtonImage(applyExtensionButton, symbolName: "arrow.clockwise")
        configureButtonImage(chooseVideoButton, symbolName: "video")
        configureButtonImage(compressVideoButton, symbolName: "film")

        tableView.headerView = nil
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.backgroundColor = .clear
        tableView.rowHeight = 38
        tableView.selectionHighlightStyle = .regular
        tableView.intercellSpacing = NSSize(width: 0, height: 8)
        tableView.target = self
        tableView.doubleAction = #selector(revealSelectedFile)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("files"))
        column.title = "Files"
        tableView.addTableColumn(column)
        tableView.delegate = self
        tableView.dataSource = self

        logTextView.isEditable = false
        logTextView.drawsBackground = true
        logTextView.backgroundColor = Palette.log
        logTextView.textColor = Palette.text
        logTextView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        logTextView.textContainerInset = NSSize(width: 16, height: 16)

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .large
        progressIndicator.isDisplayedWhenStopped = false

        batchProgressIndicator.translatesAutoresizingMaskIntoConstraints = false
        batchProgressIndicator.style = .bar
        batchProgressIndicator.isIndeterminate = false
        batchProgressIndicator.minValue = 0
        batchProgressIndicator.maxValue = 1
        batchProgressIndicator.doubleValue = 0
        batchProgressIndicator.controlSize = .regular
        batchProgressIndicator.heightAnchor.constraint(equalToConstant: 10).isActive = true

        updateSaveModeUI()
        previewCard?.isHidden = true
        previewHeightConstraint?.constant = 0
        updateResponsiveLayout(for: view.bounds.width)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateResponsiveLayout(for: view.bounds.width)
    }

    private func updateResponsiveLayout(for width: CGFloat) {
        let compact = width < 1220
        controlsRowStack?.orientation = compact ? .vertical : .horizontal
        controlsRowStack?.distribution = compact ? .fill : .fillEqually
        bottomRowStack?.orientation = compact ? .vertical : .horizontal
        bottomRowStack?.distribution = compact ? .fill : .fillEqually
    }

    private func buildHeaderCard() -> NSView {
        let card = GradientCardView(colors: [Palette.heroStart, Palette.heroEnd])

        let root = NSStackView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.orientation = .horizontal
        root.spacing = 18
        card.addSubview(root)

        let left = NSStackView()
        left.orientation = .vertical
        left.spacing = 12
        left.alignment = .leading

        let badge = makeBadgeLabel("Private on-device compression")
        let title = makeLabel(
            "Image Compression Workspace",
            size: 30,
            weight: .semibold,
            color: Palette.text
        )
        title.maximumNumberOfLines = 2

        let subtitle = makeWrappingLabel(
            "Queue image and video files, choose your output target, and run local compression with clear per-file results.",
            size: 14,
            weight: .regular,
            color: Palette.muted
        )

        let highlights = NSStackView(views: [
            makeHighlightPill(symbol: "lock.shield", text: "100% local"),
            makeHighlightPill(symbol: "video", text: "Video batch"),
            makeHighlightPill(symbol: "checkmark.square", text: "Same-name save"),
        ])
        highlights.orientation = .horizontal
        highlights.spacing = 10

        left.addArrangedSubview(badge)
        left.addArrangedSubview(title)
        left.addArrangedSubview(subtitle)
        left.addArrangedSubview(highlights)

        let previewCard = CardView(background: Palette.overlay)
        let previewStack = NSStackView()
        previewStack.translatesAutoresizingMaskIntoConstraints = false
        previewStack.orientation = .vertical
        previewStack.spacing = 8
        previewCard.addSubview(previewStack)

        let previewTitle = makeLabel("Local Compression Suite", size: 12, weight: .semibold, color: Palette.champagne)
        let previewValue = makeLabel("Images + Video", size: 27, weight: .semibold, color: Palette.text)
        let previewBody = makeWrappingLabel(
            "Images target tiny shareable output, while videos use a quality fallback ladder and pick the smallest high-quality format.",
            size: 12,
            weight: .regular,
            color: Palette.muted
        )
        previewStack.addArrangedSubview(previewTitle)
        previewStack.addArrangedSubview(previewValue)
        previewStack.addArrangedSubview(previewBody)

        NSLayoutConstraint.activate([
            previewStack.leadingAnchor.constraint(equalTo: previewCard.leadingAnchor, constant: 18),
            previewStack.trailingAnchor.constraint(equalTo: previewCard.trailingAnchor, constant: -18),
            previewStack.topAnchor.constraint(equalTo: previewCard.topAnchor, constant: 16),
            previewStack.bottomAnchor.constraint(equalTo: previewCard.bottomAnchor, constant: -16),
            previewCard.widthAnchor.constraint(equalToConstant: 280)
        ])

        root.addArrangedSubview(left)
        root.addArrangedSubview(previewCard)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: card.topAnchor, constant: 22),
            root.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -22)
        ])

        return card
    }

    private func buildTopBarCard() -> NSView {
        let card = CardView(background: Palette.cardAlt)

        let row = NSStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        card.addSubview(row)

        let titleStack = NSStackView()
        titleStack.orientation = .vertical
        titleStack.spacing = 4
        titleStack.addArrangedSubview(makeLabel("Image & Video Compressor", size: 21, weight: .semibold, color: Palette.text))
        titleStack.addArrangedSubview(
            makeWrappingLabel(
                "Everything stays local. Scroll through the queue and settings below, then run compression from here.",
                size: 12,
                weight: .regular,
                color: Palette.muted
            )
        )

        let actionGroup = NSStackView()
        actionGroup.orientation = .vertical
        actionGroup.alignment = .trailing
        actionGroup.spacing = 5
        actionGroup.addArrangedSubview(compressButton)
        actionGroup.addArrangedSubview(makeLabel("Primary action", size: 11, weight: .medium, color: Palette.subtle))

        row.addArrangedSubview(titleStack)
        row.addArrangedSubview(NSView())
        row.addArrangedSubview(actionGroup)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            compressButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
        ])

        return card
    }

    private func buildStatCard(
        title: String,
        valueLabel: NSTextField,
        detailLabel: NSTextField,
        symbol: String,
        tint: NSColor
    ) -> NSView {
        let card = CardView(background: Palette.card)
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.spacing = 10
        card.addSubview(stack)

        let topRow = NSStackView()
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 10

        topRow.addArrangedSubview(makeSymbolBadge(symbol: symbol, tint: tint))
        topRow.addArrangedSubview(makeLabel(title.uppercased(), size: 11, weight: .medium, color: Palette.subtle))
        topRow.addArrangedSubview(NSView())

        stack.addArrangedSubview(topRow)
        stack.addArrangedSubview(valueLabel)
        stack.addArrangedSubview(detailLabel)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -16)
        ])

        return card
    }

    private func buildSourcesCard() -> NSView {
        let (card, stack) = makeSectionCard(
            title: "Add your images",
            subtitle: "Drag files or folders into the drop zone, or use the quick actions below.",
            symbol: "tray.and.arrow.down.fill"
        )

        let dropZone = DropZoneView()
        dropZone.onDrop = { [weak self] urls in
            self?.addInputURLs(urls)
        }

        let firstButtonRow = NSStackView(views: [addFilesButton, addFolderButton])
        firstButtonRow.orientation = .horizontal
        firstButtonRow.spacing = 8
        firstButtonRow.distribution = .fillEqually

        let secondButtonRow = NSStackView(views: [removeSelectedButton, clearAllButton])
        secondButtonRow.orientation = .horizontal
        secondButtonRow.spacing = 8
        secondButtonRow.distribution = .fillEqually

        stack.addArrangedSubview(dropZone)
        stack.addArrangedSubview(firstButtonRow)
        stack.addArrangedSubview(secondButtonRow)
        stack.addArrangedSubview(queueHintLabel)

        return card
    }

    private func buildSettingsCard() -> NSView {
        let (card, stack) = makeSectionCard(
            title: "Choose how to save",
            subtitle: "Base filename stays the same. The app can switch format to hit 150 KB.",
            symbol: "bolt.fill"
        )

        stack.addArrangedSubview(makeFormGroup(label: "Target size", control: maxSizeField))
        stack.addArrangedSubview(targetPresetControl)

        let qualityRow = NSStackView(views: [qualitySlider, qualityValueLabel])
        qualityRow.orientation = .horizontal
        qualityRow.alignment = .centerY
        qualityRow.spacing = 12
        qualityRow.distribution = .fill
        qualityRow.isHidden = true

        let formatRow = NSStackView(views: [
            makeFormGroup(label: "Format", control: formatPopup),
            makeFormGroup(label: "Save mode", control: saveModePopup),
        ])
        formatRow.orientation = .horizontal
        formatRow.distribution = .fillEqually
        formatRow.spacing = 12
        stack.addArrangedSubview(formatRow)

        let outputRow = NSStackView()
        outputRow.orientation = .horizontal
        outputRow.spacing = 8
        outputRow.addArrangedSubview(outputFolderField)
        outputRow.addArrangedSubview(chooseOutputButton)
        outputRow.addArrangedSubview(clearOutputButton)
        stack.addArrangedSubview(makeFormGroup(label: "Output folder", control: outputRow))

        let hintCard = CardView(background: Palette.cardAlt)
        let hintStack = NSStackView()
        hintStack.translatesAutoresizingMaskIntoConstraints = false
        hintStack.orientation = .vertical
        hintStack.spacing = 8
        hintCard.addSubview(hintStack)
        hintStack.addArrangedSubview(saveModeHintLabel)
        hintStack.addArrangedSubview(
            makeWrappingLabel(
                "A 12 MB image can need both higher compression and smaller dimensions to fit inside 150 KB. This tool always aims for the best visual result under the limit.",
                size: 12,
                weight: .regular,
                color: Palette.muted
            )
        )
        NSLayoutConstraint.activate([
            hintStack.leadingAnchor.constraint(equalTo: hintCard.leadingAnchor, constant: 14),
            hintStack.trailingAnchor.constraint(equalTo: hintCard.trailingAnchor, constant: -14),
            hintStack.topAnchor.constraint(equalTo: hintCard.topAnchor, constant: 12),
            hintStack.bottomAnchor.constraint(equalTo: hintCard.bottomAnchor, constant: -12)
        ])
        stack.addArrangedSubview(hintCard)

        return card
    }

    private func buildExtensionToolCard() -> NSView {
        let (card, stack) = makeSectionCard(
            title: "Change a file extension",
            subtitle: "A separate quick rename bar. It keeps every file in the same folder and changes only the extension.",
            symbol: "doc.badge.gearshape"
        )

        let renameRow = NSStackView()
        renameRow.orientation = .horizontal
        renameRow.alignment = .bottom
        renameRow.spacing = 12
        renameRow.distribution = .fill

        let fileGroup = makeFormGroup(label: "Selected files", control: extensionFileField)
        let extensionGroup = makeFormGroup(label: "New extension", control: extensionPopup)
        extensionGroup.widthAnchor.constraint(equalToConstant: 190).isActive = true

        let extensionDropZone = ExtensionDropZoneView()
        extensionDropZone.onDrop = { [weak self] urls in
            self?.setExtensionToolFiles(urls)
        }

        extensionFileField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        chooseExtensionFileButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        applyExtensionButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        renameRow.addArrangedSubview(fileGroup)
        renameRow.addArrangedSubview(chooseExtensionFileButton)
        renameRow.addArrangedSubview(extensionGroup)
        renameRow.addArrangedSubview(applyExtensionButton)

        stack.addArrangedSubview(extensionDropZone)
        stack.addArrangedSubview(renameRow)
        stack.addArrangedSubview(extensionToolStatusLabel)

        return card
    }

    private func buildVideoCompressionCard() -> NSView {
        let (card, stack) = makeSectionCard(
            title: "Compress video",
            subtitle: "Compress videos at quality 18 first, then 20 or 21 only if needed.",
            symbol: "video.badge.waveform"
        )

        let summaryRow = NSStackView()
        summaryRow.orientation = .horizontal
        summaryRow.alignment = .centerY
        summaryRow.spacing = 12
        summaryRow.distribution = .fillEqually

        let sourceTile = makeVideoCompressionTile(
            title: "Source",
            value: "Up to 10 MB",
            detail: "recommended input"
        )
        let targetTile = makeVideoCompressionTile(
            title: "Format",
            value: "Auto",
            detail: "WebM or MP4"
        )
        let qualityTile = makeVideoCompressionTile(
            title: "Quality",
            value: "High",
            detail: "18 -> 20 -> 21"
        )

        summaryRow.addArrangedSubview(sourceTile)
        summaryRow.addArrangedSubview(targetTile)
        summaryRow.addArrangedSubview(qualityTile)
        stack.addArrangedSubview(summaryRow)

        let controlRow = NSStackView()
        controlRow.orientation = .horizontal
        controlRow.alignment = .bottom
        controlRow.spacing = 12
        controlRow.distribution = .fill

        let videoGroup = makeFormGroup(label: "Selected video", control: videoFileField)
        let targetGroup = makeFormGroup(label: "Target size", control: videoTargetField)
        targetGroup.widthAnchor.constraint(equalToConstant: 150).isActive = true

        let videoDropZone = VideoDropZoneView()
        videoDropZone.onDrop = { [weak self] urls in
            self?.setVideoFiles(urls)
        }

        videoFileField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        chooseVideoButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        compressVideoButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        controlRow.addArrangedSubview(videoGroup)
        controlRow.addArrangedSubview(chooseVideoButton)
        controlRow.addArrangedSubview(targetGroup)
        controlRow.addArrangedSubview(compressVideoButton)

        stack.addArrangedSubview(videoDropZone)
        stack.addArrangedSubview(controlRow)
        stack.addArrangedSubview(videoStatusLabel)

        return card
    }

    private func makeVideoCompressionTile(title: String, value: String, detail: String) -> NSView {
        let tile = NSView()
        tile.translatesAutoresizingMaskIntoConstraints = false
        tile.wantsLayer = true
        tile.layer?.backgroundColor = Palette.cardAlt.cgColor
        tile.layer?.cornerRadius = 14
        tile.layer?.borderWidth = 1
        tile.layer?.borderColor = Palette.border.cgColor

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        tile.addSubview(stack)

        stack.addArrangedSubview(makeLabel(title, size: 11, weight: .semibold, color: Palette.muted))
        stack.addArrangedSubview(makeLabel(value, size: 20, weight: .semibold, color: Palette.text))
        stack.addArrangedSubview(makeLabel(detail, size: 11, weight: .regular, color: Palette.muted))

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: tile.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: tile.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: tile.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: tile.bottomAnchor, constant: -12),
            tile.heightAnchor.constraint(greaterThanOrEqualToConstant: 86)
        ])

        return tile
    }

    private func buildPreviewCard() -> NSView {
        let (card, stack) = makeSectionCard(
            title: "Live quality preview",
            subtitle: "The first queued image is recompressed locally after you move the slider.",
            symbol: "photo.on.rectangle.angled"
        )

        let imageRow = NSStackView()
        imageRow.orientation = .vertical
        imageRow.spacing = 10
        imageRow.distribution = .fillEqually

        imageRow.addArrangedSubview(makePreviewColumn(label: previewOriginalLabel, imageView: previewOriginalImageView))
        imageRow.addArrangedSubview(makePreviewColumn(label: previewOutputLabel, imageView: previewOutputImageView))

        stack.addArrangedSubview(imageRow)
        stack.addArrangedSubview(previewStatusLabel)

        return card
    }

    private func makePreviewColumn(label: NSTextField, imageView: NSImageView) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.addArrangedSubview(label)
        stack.addArrangedSubview(imageView)
        return stack
    }

    private func buildQueueCard() -> NSView {
        let (card, stack) = makeSectionCard(
            title: "Review the queue",
            subtitle: "Double-click any file to reveal it in Finder.",
            symbol: "list.bullet.rectangle.portrait"
        )

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = Palette.log
        scroll.documentView = tableView
        tableView.enclosingScrollView?.drawsBackground = true

        stack.addArrangedSubview(scroll)
        scroll.heightAnchor.constraint(equalToConstant: 150).isActive = true
        return card
    }

    private func buildLogCard() -> NSView {
        let (card, stack) = makeSectionCard(
            title: "Follow the results",
            subtitle: "Every processed file writes a line here so you can see exactly what happened.",
            symbol: "terminal"
        )

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = Palette.log
        scroll.documentView = logTextView

        let progressRow = NSStackView()
        progressRow.orientation = .horizontal
        progressRow.alignment = .centerY
        progressRow.spacing = 12
        progressRow.addArrangedSubview(batchProgressIndicator)
        progressRow.addArrangedSubview(batchProgressLabel)
        batchProgressIndicator.setContentHuggingPriority(.defaultLow, for: .horizontal)
        batchProgressLabel.setContentHuggingPriority(.required, for: .horizontal)

        stack.addArrangedSubview(progressRow)
        stack.addArrangedSubview(scroll)
        scroll.heightAnchor.constraint(equalToConstant: 122).isActive = true
        return card
    }

    private func buildFooterCard() -> NSView {
        let card = CardView()
        let container = NSStackView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.orientation = .horizontal
        container.alignment = .centerY
        container.spacing = 16
        card.addSubview(container)

        let left = NSStackView()
        left.orientation = .horizontal
        left.alignment = .centerY
        left.spacing = 14
        left.addArrangedSubview(progressIndicator)
        left.addArrangedSubview(statusLabel)
        left.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let right = NSStackView(views: [stopButton, openOutputButton])
        right.orientation = .horizontal
        right.spacing = 10
        right.setContentHuggingPriority(.required, for: .horizontal)

        container.addArrangedSubview(left)
        container.addArrangedSubview(NSView())
        container.addArrangedSubview(right)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            container.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            container.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            container.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])

        return card
    }

    private func makeSectionCard(title: String, subtitle: String, symbol: String) -> (CardView, NSStackView) {
        let card = CardView()
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.spacing = 12
        card.addSubview(stack)

        let titleRow = NSStackView()
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 10
        titleRow.addArrangedSubview(makeSymbolBadge(symbol: symbol, tint: Palette.accent))
        titleRow.addArrangedSubview(makeLabel(title, size: 19, weight: .semibold, color: Palette.text))
        titleRow.addArrangedSubview(NSView())

        stack.addArrangedSubview(titleRow)
        stack.addArrangedSubview(makeWrappingLabel(subtitle, size: 12, weight: .regular, color: Palette.muted))

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18)
        ])

        return (card, stack)
    }

    private func makeFormGroup(label: String, control: NSView) -> NSView {
        let group = NSStackView()
        group.orientation = .vertical
        group.spacing = 8
        group.addArrangedSubview(makeLabel(label.uppercased(), size: 11, weight: .medium, color: Palette.subtle))
        group.addArrangedSubview(control)
        return group
    }

    @objc private func setTargetFromPreset(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue else { return }
        maxSizeField.stringValue = raw
        updateDashboard()
    }

    @objc private func setTargetFromSegment(_ sender: NSSegmentedControl) {
        let values = ["150kb", "300kb", "500kb"]
        guard sender.selectedSegment >= 0, sender.selectedSegment < values.count else { return }
        maxSizeField.stringValue = values[sender.selectedSegment]
        updateDashboard()
    }

    @objc private func qualitySliderChanged(_ sender: NSSlider) {
        qualityValueLabel.stringValue = "\(Int(sender.doubleValue.rounded()))%"
        updateDashboard()
        schedulePreviewUpdate()
    }

    @objc private func toggleLivePreview(_ sender: NSButton) {
        let shouldShow = sender.state == .on
        sender.title = shouldShow ? "Hide Live Preview" : "Show Live Preview"
        previewCard?.isHidden = !shouldShow
        previewHeightConstraint?.constant = shouldShow ? 330 : 0
        view.layoutSubtreeIfNeeded()

        if shouldShow {
            schedulePreviewUpdate()
        } else {
            previewWorkItem?.cancel()
            previewOutputImageView.image = nil
            previewStatusLabel.stringValue = "Live preview is hidden."
        }
    }

    @objc func addFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = []
        if panel.runModal() == .OK {
            addInputURLs(panel.urls)
        }
    }

    @objc func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            addInputURLs(panel.urls)
        }
    }

    @objc private func removeSelected() {
        let indexes = tableView.selectedRowIndexes
        guard !indexes.isEmpty else { return }
        selectedFiles = selectedFiles.enumerated().filter { !indexes.contains($0.offset) }.map(\.element)
        refreshQueue()
        statusLabel.stringValue = "Removed the selected item(s) from the queue."
        saveSessionState()
    }

    @objc func clearAll() {
        selectedFiles.removeAll()
        refreshQueue()
        resetBatchProgress()
        saveSessionState()
        statusLabel.stringValue = "Queue cleared. Add new files whenever you are ready."
    }


    private func saveSessionState() {
        let payload: [String: Any] = [
            "files": selectedFiles.map { $0.path },
            "maxSize": maxSizeField.stringValue,
            "mode": saveModePopup.titleOfSelectedItem ?? "same-name",
            "output": outputFolderField.stringValue
        ]
        UserDefaults.standard.set(payload, forKey: sessionStateKey)
    }

    private func restoreSessionState() {
        guard let payload = UserDefaults.standard.dictionary(forKey: sessionStateKey) else { return }
        if let files = payload["files"] as? [String] {
            let urls = files.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
            addInputURLs(urls)
        }
        if let max = payload["maxSize"] as? String { maxSizeField.stringValue = max }
        if let mode = payload["mode"] as? String { saveModePopup.selectItem(withTitle: mode) }
        if let out = payload["output"] as? String { outputFolderField.stringValue = out }
        updateSaveModeUI()
        updateDashboard()
    }

    private func promptAndRestoreSessionState() {
        guard UserDefaults.standard.dictionary(forKey: sessionStateKey) != nil else { return }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Restore previous session?"
        alert.informativeText = "Restore your previous queue and settings."
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Start Fresh")
        if alert.runModal() == .alertFirstButtonReturn {
            restoreSessionState()
        }
    }

    @objc func reloadSession() {
        if isRunning {
            showAlert(title: "Compression is running", message: "Wait for the current compression to finish before reloading the session.")
            return
        }

        selectedFiles.removeAll()
        lastOutputFolder = nil
        outputFolderField.stringValue = ""
        openOutputButton.isEnabled = false

        extensionToolFileURLs.removeAll()
        extensionFileField.stringValue = "No file selected"
        extensionPopup.selectItem(withTitle: "webp")
        extensionToolStatusLabel.stringValue = "Pick one or more files, type the new extension, then rename them in the same folder."
        applyExtensionButton.isEnabled = false

        previewWorkItem?.cancel()
        previewRequestID = UUID()
        previewToggleButton.state = .off
        previewToggleButton.title = "Show Live Preview"
        previewCard?.isHidden = true
        previewHeightConstraint?.constant = 0
        previewOriginalImageView.image = nil
        previewOutputImageView.image = nil
        previewOriginalLabel.stringValue = "Original"
        previewOutputLabel.stringValue = "Move the slider"
        previewStatusLabel.stringValue = "Add an image to see a live quality preview."

        logTextView.string = ""
        resetBatchProgress()
        setRunning(false)
        refreshQueue()
        statusLabel.stringValue = "Fresh session ready. Add files and press Compress Now."
        appendLog("Session reloaded. Ready for new files.")
    }

    @objc func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            outputFolderField.stringValue = url.path
        }
    }

    @objc private func clearOutputFolder() {
        outputFolderField.stringValue = ""
    }

    @objc func chooseExtensionFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = []
        if panel.runModal() == .OK {
            setExtensionToolFiles(panel.urls)
        }
    }

    private func setExtensionToolFiles(_ urls: [URL]) {
        let fileURLs = urls.filter { !$0.hasDirectoryPath }
        guard !fileURLs.isEmpty else {
            extensionToolStatusLabel.stringValue = "Drop or choose files only. Folders are ignored for extension changes."
            appendLog("Extension tool ignored a drop with no files.")
            return
        }

        extensionToolFileURLs = fileURLs
        if fileURLs.count == 1, let url = fileURLs.first {
            extensionFileField.stringValue = url.path
        } else {
            extensionFileField.stringValue = "\(fileURLs.count) files selected"
        }
        applyExtensionButton.isEnabled = true
        if let url = fileURLs.first {
            let currentExtension = url.pathExtension.lowercased()
            if extensionPopup.itemTitles.contains(currentExtension) {
                extensionPopup.selectItem(withTitle: currentExtension)
            }
        }
        extensionToolStatusLabel.stringValue = "Ready to rename \(fileURLs.count) file(s)."
        appendLog("Extension tool selected \(fileURLs.count) file(s).")
    }

    @objc func applyExtensionChange() {
        guard !extensionToolFileURLs.isEmpty else {
            showAlert(title: "No files selected", message: "Choose one or more files before changing extensions.")
            return
        }

        let rawExtension = (extensionPopup.titleOfSelectedItem ?? "webp")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let normalizedExtension = rawExtension.lowercased()

        guard !normalizedExtension.isEmpty else {
            showAlert(title: "Missing extension", message: "Type the new extension without the dot, for example webp or png.")
            return
        }

        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        guard normalizedExtension.rangeOfCharacter(from: allowedCharacters.inverted) == nil else {
            showAlert(title: "Invalid extension", message: "Use only letters, numbers, hyphens, or underscores.")
            return
        }

        var renamedURLs: [URL] = []
        var renamedCount = 0
        var skippedCount = 0
        var errorCount = 0

        for sourceURL in extensionToolFileURLs {
            let destinationURL = sourceURL.deletingPathExtension().appendingPathExtension(normalizedExtension)

            if destinationURL.path == sourceURL.path {
                skippedCount += 1
                appendLog("Extension tool skipped: \(sourceURL.lastPathComponent) already uses .\(normalizedExtension)")
                renamedURLs.append(sourceURL)
                continue
            }

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                skippedCount += 1
                appendLog("[WARN] Extension tool skipped existing file: \(destinationURL.lastPathComponent)")
                renamedURLs.append(sourceURL)
                continue
            }

            do {
                try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
                renamedCount += 1
                renamedURLs.append(destinationURL)
                appendLog("Extension tool renamed: \(sourceURL.lastPathComponent) -> \(destinationURL.lastPathComponent)")
            } catch {
                errorCount += 1
                renamedURLs.append(sourceURL)
                logger.write("[ERROR] Extension rename failed for \(sourceURL.lastPathComponent): \(error.localizedDescription)")
                appendLog("[ERROR] Extension rename failed for \(sourceURL.lastPathComponent): \(error.localizedDescription)")
            }
        }

        extensionToolFileURLs = renamedURLs
        extensionPopup.selectItem(withTitle: normalizedExtension)
        if renamedURLs.count == 1, let url = renamedURLs.first {
            extensionFileField.stringValue = url.path
        } else {
            extensionFileField.stringValue = "\(renamedURLs.count) files selected"
        }

        let summary = "Renamed \(renamedCount), skipped \(skippedCount), errors \(errorCount)."
        extensionToolStatusLabel.stringValue = summary
        appendLog("Extension tool finished. \(summary)")

        if errorCount > 0 {
            showAlert(title: "Some files could not be renamed", message: summary)
        } else if skippedCount > 0 {
            showAlert(title: "Some files were skipped", message: summary)
        }
    }

    @objc func chooseVideoFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = []
        if panel.runModal() == .OK {
            setVideoFiles(panel.urls)
        }
    }

    private func setVideoFiles(_ urls: [URL]) {
        let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "webm", "avi", "mkv", "hevc", "h265"]
        let fileURLs = urls.filter { url in
            !url.hasDirectoryPath && videoExtensions.contains(url.pathExtension.lowercased())
        }

        guard !fileURLs.isEmpty else {
            videoStatusLabel.stringValue = "Drop or choose video files only."
            appendLog("Video block ignored a selection with no video files.")
            return
        }

        videoFileURLs = fileURLs
        compressVideoButton.isEnabled = true

        if fileURLs.count == 1, let url = fileURLs.first {
            videoFileField.stringValue = url.path
            let sizeText: String
            if let values = try? url.resourceValues(forKeys: [.fileSizeKey]), let size = values.fileSize {
                sizeText = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
            } else {
                sizeText = "selected"
            }
            videoStatusLabel.stringValue = "Ready to compress \(url.lastPathComponent) (\(sizeText)) to \(videoTargetField.stringValue)."
        } else {
            videoFileField.stringValue = "\(fileURLs.count) videos selected"
            videoStatusLabel.stringValue = "Ready to compress \(fileURLs.count) videos to \(videoTargetField.stringValue)."
        }

        appendLog("Video block selected \(fileURLs.count) video file(s).")
    }

    @objc func startVideoCompression() {
        guard !videoFileURLs.isEmpty else {
            showAlert(title: "No video selected", message: "Choose one or more videos before compressing.")
            return
        }

        let targetSize = videoTargetField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetSize.isEmpty else {
            showAlert(title: "Missing mode value", message: "Use auto for high-quality mode.")
            return
        }

        guard
            let resourceURL = Bundle.main.resourceURL,
            FileManager.default.fileExists(atPath: resourceURL.appendingPathComponent("runtime/compress_video.py").path)
        else {
            showAlert(title: "Missing video compressor", message: "The bundled video compressor file was not found.")
            return
        }

        let runtimeURL = resourceURL.appendingPathComponent("runtime", isDirectory: true)
        let scriptURL = runtimeURL.appendingPathComponent("compress_video.py")
        let bundledPython3 = runtimeURL.appendingPathComponent(".venv/bin/python3").path
        let bundledPython = runtimeURL.appendingPathComponent(".venv/bin/python").path
        let pythonPath: String
        if FileManager.default.fileExists(atPath: bundledPython3) {
            pythonPath = bundledPython3
        } else if FileManager.default.fileExists(atPath: bundledPython) {
            pythonPath = bundledPython
        } else {
            pythonPath = "/usr/bin/python3"
        }

        chooseVideoButton.isEnabled = false
        compressVideoButton.isEnabled = false
        lastOutputFolder = nil
        openOutputButton.isEnabled = false
        let files = videoFileURLs
        videoStatusLabel.stringValue = "Compressing \(files.count) video(s) to \(targetSize)..."
        appendLog("")
        appendLog("Video block starting \(files.count) video file(s)...")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var succeededCount = 0
            var failedCount = 0
            var lastFolder: URL?

            for (index, videoURL) in files.enumerated() {
                DispatchQueue.main.async {
                    self?.videoStatusLabel.stringValue = "Compressing video \(index + 1) of \(files.count): \(videoURL.lastPathComponent)"
                    self?.appendLog("")
                    self?.appendLog("Video block starting: \(videoURL.lastPathComponent)")
                }

                let process = Process()
                process.executableURL = URL(fileURLWithPath: pythonPath)
                process.currentDirectoryURL = runtimeURL
                process.arguments = [scriptURL.path, videoURL.path, "-s", targetSize]

                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    failedCount += 1
                    DispatchQueue.main.async {
                        self?.appendLog("[ERROR] Video block failed to start for \(videoURL.lastPathComponent): \(error.localizedDescription)")
                    }
                    continue
                }

                let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let lines = (output + "\n" + errorOutput)
                    .split(separator: "\n")
                    .map(String.init)
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                let succeeded = process.terminationStatus == 0

                if succeeded {
                    succeededCount += 1
                    lastFolder = videoURL.deletingLastPathComponent()
                } else {
                    failedCount += 1
                }

                DispatchQueue.main.async {
                    for line in lines {
                        self?.appendLog(line)
                    }
                }
            }

            DispatchQueue.main.async {
                guard let self else { return }
                self.chooseVideoButton.isEnabled = true
                self.compressVideoButton.isEnabled = true
                if failedCount == 0 {
                    self.videoStatusLabel.stringValue = "Video compression finished for \(succeededCount) video(s)."
                } else {
                    self.videoStatusLabel.stringValue = "Finished \(succeededCount) video(s), \(failedCount) failed. Review the log."
                }
                if let lastFolder {
                    self.lastOutputFolder = lastFolder
                    self.openOutputButton.isEnabled = true
                }
                if failedCount > 0 {
                    self.showAlert(title: "Some videos failed", message: "Finished \(succeededCount) video(s), \(failedCount) failed. Review the log for details.")
                }
            }
        }
    }

    @objc func openOutputFolder() {
        guard let folder = lastOutputFolder else { return }
        NSWorkspace.shared.open(folder)
    }

    @objc func stopCompression() {
        guard isRunning else { return }

        compressionProcessLock.lock()
        stopRequested = true
        let processes = activeCompressionProcesses
        compressionProcessLock.unlock()

        for process in processes where process.isRunning {
            process.terminate()
        }

        statusLabel.stringValue = "Stopping compression. Waiting for active files to exit..."
        appendLog("[STOPPED] Stop requested. Terminating \(processes.count) active compression process(es).")
    }

    @objc private func revealSelectedFile() {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard row >= 0, row < selectedFiles.count else { return }
        NSWorkspace.shared.activateFileViewerSelecting([selectedFiles[row]])
    }


    private func recommendedWorkerCount(for files: [URL]) -> Int {
        guard !files.isEmpty else { return 1 }
        let sizes = files.compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }.map(Int64.init)
        guard !sizes.isEmpty else { return max(1, min(files.count, 8)) }
        let total = sizes.reduce(0, +)
        let avgMB = Double(total) / Double(sizes.count) / (1024 * 1024)
        let cpu = ProcessInfo.processInfo.activeProcessorCount
        let cap: Int
        if avgMB >= 40 { cap = 2 }
        else if avgMB >= 25 { cap = 3 }
        else if avgMB >= 12 { cap = 4 }
        else if avgMB >= 6 { cap = 6 }
        else { cap = 8 }
        return max(1, min(files.count, min(cpu, cap)))
    }

    private func queueStatusKey(_ url: URL) -> String {
        url.standardizedFileURL.path
    }

    private func setFileStatus(_ url: URL, _ status: QueueFileStatus) {
        fileStates[queueStatusKey(url), default: QueueFileState()].status = status
        DispatchQueue.main.async { [weak self] in self?.tableView.reloadData() }
    }

    private func parseStatusFromLines(_ lines: [String]) -> QueueFileStatus {
        if lines.contains(where: { $0.contains("[ERROR]") }) { return .failed }
        if lines.contains(where: { $0.contains("[BEST EFFORT]") }) { return .bestEffort }
        if lines.contains(where: { $0.contains("[UNCHANGED]") }) { return .skipped }
        return .done
    }

    @objc private func saveModeChanged() {
        updateSaveModeUI()
        updateDashboard()
    }

    @objc func startCompression() {
        if isRunning { return }
        if selectedFiles.isEmpty {
            showAlert(title: "No files", message: "Add at least one image or folder first.")
            return
        }

        let mode = saveModePopup.titleOfSelectedItem ?? "same-name"
        if mode == "same-name" && outputFolderField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            showAlert(
                title: "Output folder required",
                message: "Choose an output folder so the optimized file can keep the same base name and extension."
            )
            return
        }

        let settings = currentSettings()
        guard settings != nil else { return }
        guard let resolvedSettings = settings else { return }

        lastOutputFolder = nil
        openOutputButton.isEnabled = false
        resetCompressionStopState()
        setRunning(true)
        resetBatchProgress(total: selectedFiles.count)
        resetPendingBatchUI()
        appendLog("")
        appendLog("Starting fast compression for \(selectedFiles.count) file(s)...")
        statusLabel.stringValue = "Compressing your images in ultra-fast batch mode..."

        let files = selectedFiles
        compressionRunStartedAt = Date()
        for f in files { setFileStatus(f, .queued) }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            var warningCount = 0
            var errorCount = 0
            var completedCount = 0
            var outputFolder = resolvedSettings.outputFolder
            let lock = NSLock()
            let group = DispatchGroup()
            let workerCount = self.recommendedWorkerCount(for: files)
            let semaphore = DispatchSemaphore(value: workerCount)

            for fileURL in files {
                semaphore.wait()
                if self.isCompressionStopRequested() {
                    semaphore.signal()
                    break
                }
                group.enter()

                DispatchQueue.global(qos: .userInitiated).async {
                    self.setFileStatus(fileURL, .processing)
                    let result = self.runCompression(fileURL: fileURL, settings: resolvedSettings)
                    self.setFileStatus(fileURL, self.parseStatusFromLines(result.lines))

                    lock.lock()
                    warningCount += result.bestEffort ? 1 : 0
                    errorCount += result.hadError ? 1 : 0
                    completedCount += 1
                    let completed = completedCount
                    if outputFolder == nil {
                        outputFolder = fileURL.deletingLastPathComponent()
                    }
                    self.queueBatchUIUpdate(lines: result.lines, completed: completed, total: files.count)
                    if let started = self.compressionRunStartedAt {
                        let elapsed = max(Date().timeIntervalSince(started), 0.001)
                        let rate = Double(completed) / elapsed
                        let remaining = max(files.count - completed, 0)
                        let eta = rate > 0 ? Double(remaining) / rate : 0
                        let etaText = String(format: "%.0fs", eta)
                        DispatchQueue.main.async { [weak self] in
                            self?.statusLabel.stringValue = "Compressing: \(completed)/\(files.count) done | \(String(format: "%.2f", rate)) files/s | ETA \(etaText)"
                        }
                    }
                    lock.unlock()

                    semaphore.signal()
                    group.leave()
                }
            }

            group.wait()

            let summary: String
            lock.lock()
            let finalCompletedCount = completedCount
            lock.unlock()

            if self.isCompressionStopRequested() {
                summary = "Stopped. \(finalCompletedCount) complete / \(max(files.count - finalCompletedCount, 0)) left."
            } else if errorCount > 0 {
                summary = "Finished with \(errorCount) error(s). Review the log for details."
            } else if warningCount > 0 {
                summary = "Finished. \(warningCount) file(s) reached BEST EFFORT instead of the exact target."
            } else {
                summary = "Finished. \(files.count) file(s) processed successfully."
            }

            DispatchQueue.main.async {
                self.flushPendingBatchUI(total: files.count, autoScroll: false)
                self.statusLabel.stringValue = summary
                self.setRunning(false)
                self.appendLog(summary)
                self.lastOutputFolder = outputFolder
                self.openOutputButton.isEnabled = outputFolder != nil
                if let folder = outputFolder {
                    self.appendLog("Output folder: \(folder.path)")
                }
                self.sendCompletionNotification(summary)
            }
        }
    }

    private func currentSettings() -> CompressionSettings? {
        let maxSize = maxSizeField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if maxSize.isEmpty {
            showAlert(title: "Invalid target size", message: "Enter a value like 150kb or 0.5mb.")
            return nil
        }

        let mode = saveModePopup.titleOfSelectedItem ?? "same-name"
        let format = "auto"
        let outputText = outputFolderField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        var outputFolder: URL?
        if !outputText.isEmpty && mode != "overwrite" {
            let folder = URL(fileURLWithPath: outputText)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                outputFolder = folder
            } catch {
                showAlert(
                    title: "Invalid output folder",
                    message: "Could not use the selected output folder.\n\n\(error.localizedDescription)"
                )
                return nil
            }
        }

        return CompressionSettings(
            maxSize: maxSize,
            outputFormat: format,
            nameMode: mode,
            outputFolder: outputFolder
        )
    }

    private func runCompression(fileURL: URL, settings: CompressionSettings) -> CompressionRunResult {
        guard
            let resourceURL = Bundle.main.resourceURL,
            FileManager.default.fileExists(atPath: resourceURL.appendingPathComponent("runtime/compress_image.py").path)
        else {
            let line = "[ERROR] Missing bundled compressor runtime."
            logger.write(line)
            return CompressionRunResult(lines: [line], hadError: true, bestEffort: false)
        }

        let runtimeURL = resourceURL.appendingPathComponent("runtime", isDirectory: true)
        let scriptURL = runtimeURL.appendingPathComponent("compress_image.py")

        let process = Process()
        let bundledPython3 = runtimeURL.appendingPathComponent(".venv/bin/python3").path
        let bundledPython = runtimeURL.appendingPathComponent(".venv/bin/python").path
        let pythonPath: String
        if FileManager.default.fileExists(atPath: bundledPython3) {
            pythonPath = bundledPython3
        } else if FileManager.default.fileExists(atPath: bundledPython) {
            pythonPath = bundledPython
        } else {
            pythonPath = "/usr/bin/python3"
        }
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.currentDirectoryURL = runtimeURL

        var arguments = [scriptURL.path, fileURL.path]
        if let outputFolder = settings.outputFolder, settings.nameMode != "overwrite" {
            arguments.append(outputFolder.path)
        }
        arguments.append(contentsOf: [
            "-s", settings.maxSize,
            "--format", settings.outputFormat,
            "--name-mode", settings.nameMode,
            "--min-quality", "20",
            "--max-quality", "100",
            "--min-side", "320",
            "--background", "FFFFFF",
        ])
        process.arguments = arguments

        if settings.nameMode == "same-name",
           let outputFolder = settings.outputFolder,
           let srcDate = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
            let base = fileURL.deletingPathExtension().lastPathComponent
            let candidates = ["webp", "jpg", "jpeg", "png"].map { outputFolder.appendingPathComponent(base).appendingPathExtension($0) }
            let newestExisting = candidates
                .filter { FileManager.default.fileExists(atPath: $0.path) }
                .compactMap { url in
                    (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate).map { (url, $0) }
                }
                .max { $0.1 < $1.1 }

            if let (existingURL, outDate) = newestExisting, outDate >= srcDate {
                let line = "[UNCHANGED] \(fileURL.lastPathComponent) already has a newer output (\(existingURL.lastPathComponent)). Skipped."
                logger.write(line)
                return CompressionRunResult(lines: [line], hadError: false, bestEffort: false)
            }
        }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        if isCompressionStopRequested() {
            return CompressionRunResult(
                lines: ["[STOPPED] \(fileURL.lastPathComponent) skipped before starting."],
                hadError: false,
                bestEffort: false
            )
        }

        var launchError: Error?
        for attempt in 1...2 {
            do {
                try process.run()
                registerCompressionProcess(process)
                process.waitUntilExit()
                unregisterCompressionProcess(process)
                launchError = nil
                break
            } catch {
                unregisterCompressionProcess(process)
                launchError = error
                if attempt == 1 {
                    Thread.sleep(forTimeInterval: 0.15)
                }
            }
        }
        if let error = launchError {
            let line = "[ERROR] \(fileURL.lastPathComponent) | \(error.localizedDescription)"
            logger.write(line)
            return CompressionRunResult(lines: [line], hadError: true, bestEffort: false)
        }

        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        var lines = stdout
            .split(whereSeparator: \.isNewline)
            .map { String($0) }

        let trimmedError = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedError.isEmpty {
            lines.append(contentsOf: trimmedError.split(whereSeparator: \.isNewline).map { chunk in
                let text = String(chunk)
                return text.hasPrefix("Error:") ? "[ERROR] \(text.dropFirst(6).trimmingCharacters(in: .whitespaces))" : "[ERROR] \(text)"
            })
        }

        if lines.isEmpty {
            lines = ["[INFO] \(fileURL.lastPathComponent) processed."]
        }

        if isCompressionStopRequested(), process.terminationStatus != 0 {
            lines = ["[STOPPED] \(fileURL.lastPathComponent) stopped before finishing."]
        } else if process.terminationStatus != 0, trimmedError.isEmpty {
            lines.append("[ERROR] \(fileURL.lastPathComponent) exited with code \(process.terminationStatus).")
        }

        lines.forEach(logger.write)
        return CompressionRunResult(
            lines: lines,
            hadError: !trimmedError.isEmpty || (!isCompressionStopRequested() && process.terminationStatus != 0),
            bestEffort: lines.contains { $0.contains("[BEST EFFORT]") }
        )
    }

    private func schedulePreviewUpdate() {
        previewWorkItem?.cancel()
        previewRequestID = UUID()
        let requestID = previewRequestID

        guard previewToggleButton.state == .on else {
            return
        }

        guard let fileURL = selectedFiles.first else {
            previewOriginalImageView.image = nil
            previewOutputImageView.image = nil
            previewOriginalLabel.stringValue = "Original"
            previewOutputLabel.stringValue = "Move the slider"
            previewStatusLabel.stringValue = "Add an image to see a live quality preview."
            return
        }

        let quality = Int(qualitySlider.doubleValue.rounded())
        let maxSize = maxSizeField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        previewOriginalImageView.image = NSImage(contentsOf: fileURL)
        previewOutputImageView.image = nil
        previewOriginalLabel.stringValue = "Original"
        previewOutputLabel.stringValue = "Rendering..."
        previewStatusLabel.stringValue = "Rendering preview at \(quality)% quality."

        let workItem = DispatchWorkItem { [weak self] in
            DispatchQueue.global(qos: .userInitiated).async {
                self?.renderPreview(fileURL: fileURL, maxSize: maxSize, quality: quality, requestID: requestID)
            }
        }

        previewWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: workItem)
    }

    private func renderPreview(fileURL: URL, maxSize: String, quality: Int, requestID: UUID) {
        let cacheKey = "\(fileURL.path)|\(maxSize)|\(quality)"
        if let cached = previewCache[cacheKey] {
            updatePreviewIfCurrent(requestID: requestID, image: NSImage(data: cached.imageData), outputText: cached.outputText, status: cached.status)
            return
        }
        guard
            let resourceURL = Bundle.main.resourceURL,
            FileManager.default.fileExists(atPath: resourceURL.appendingPathComponent("runtime/compress_image.py").path)
        else {
            updatePreviewIfCurrent(requestID: requestID, image: nil, outputText: "Preview unavailable", status: "Missing bundled compressor runtime.")
            return
        }

        let runtimeURL = resourceURL.appendingPathComponent("runtime", isDirectory: true)
        let scriptURL = runtimeURL.appendingPathComponent("compress_image.py")
        let bundledPython3 = runtimeURL.appendingPathComponent(".venv/bin/python3").path
        let bundledPython = runtimeURL.appendingPathComponent(".venv/bin/python").path
        let pythonPath: String
        if FileManager.default.fileExists(atPath: bundledPython3) {
            pythonPath = bundledPython3
        } else if FileManager.default.fileExists(atPath: bundledPython) {
            pythonPath = bundledPython
        } else {
            pythonPath = "/usr/bin/python3"
        }

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("image-compressor-preview-\(UUID().uuidString)", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        } catch {
            updatePreviewIfCurrent(requestID: requestID, image: nil, outputText: "Preview unavailable", status: error.localizedDescription)
            return
        }
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.currentDirectoryURL = runtimeURL
        process.arguments = [
            scriptURL.path,
            fileURL.path,
            tempRoot.path,
            "-s", maxSize.isEmpty ? "150kb" : maxSize,
            "--format", "keep",
            "--name-mode", "same-name",
            "--min-quality", "1",
            "--max-quality", String(max(1, quality)),
            "--min-side", "320",
            "--background", "FFFFFF",
            "--keep-dimensions",
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            updatePreviewIfCurrent(requestID: requestID, image: nil, outputText: "Preview failed", status: error.localizedDescription)
            return
        }

        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let statusLine = stdout.split(whereSeparator: \.isNewline).first.map(String.init)
            ?? stderr.split(whereSeparator: \.isNewline).first.map(String.init)
            ?? "Preview rendered."

        let outputURL = previewOutputFile(in: tempRoot)
        let outputData = outputURL.flatMap { try? Data(contentsOf: $0) }
        let outputImage = outputData.flatMap(NSImage.init(data:))
        let originalSize = fileSizeText(fileURL)
        let outputSize = outputURL.map(fileSizeText) ?? "n/a"
        let outputText = "Split preview | \(quality)% -> \(outputSize)"
        let status = "\(fileURL.lastPathComponent): \(originalSize) -> \(outputSize). \(statusLine)"

        if let data = outputData {
            previewCache[cacheKey] = PreviewCacheEntry(imageData: data, outputText: outputText, status: status)
        }
        updatePreviewIfCurrent(requestID: requestID, image: outputImage, outputText: outputText, status: status)
    }

    private func previewOutputFile(in folder: URL) -> URL? {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return urls.first { url in
            supportedExtensions.contains(url.pathExtension.lowercased())
        }
    }

    private func updatePreviewIfCurrent(requestID: UUID, image: NSImage?, outputText: String, status: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.previewRequestID == requestID else { return }
            self.previewOutputImageView.image = image
            self.previewOutputLabel.stringValue = outputText
            self.previewStatusLabel.stringValue = status
        }
    }

    private func fileSizeText(_ url: URL) -> String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private func addInputURLs(_ urls: [URL]) {
        var seen = Set(selectedFiles.map { $0.standardizedFileURL.path })
        var added = 0

        for url in urls {
            for file in collectInputFiles(from: url) {
                let key = file.standardizedFileURL.path
                if !seen.contains(key) {
                    selectedFiles.append(file)
                    seen.insert(key)
                    fileStates[key] = QueueFileState(status: .queued)
                    added += 1
                }
            }
        }

        refreshQueue()
        if added > 0 {
            statusLabel.stringValue = "Added \(added) file(s) to the queue."
            saveSessionState()
        } else {
            statusLabel.stringValue = "No supported image files were found in that selection."
        }
    }

    private func collectInputFiles(from url: URL) -> [URL] {
        var files: [URL] = []
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return files
        }

        if !isDirectory.boolValue {
            return isSupportedImage(url) ? [url] : []
        }

        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return files
        }

        for case let candidate as URL in enumerator {
            if isSupportedImage(candidate) {
                files.append(candidate)
            }
        }
        return files
    }

    private func isSupportedImage(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    private func refreshQueue() {
        selectedFiles.sort { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
        let live = Set(selectedFiles.map { queueStatusKey($0) })
        fileStates = fileStates.filter { live.contains($0.key) }
        tableView.reloadData()
        updateDashboard()
        schedulePreviewUpdate()

        if selectedFiles.isEmpty {
            queueHintLabel.stringValue = "Nothing is queued yet. Add files, add a folder, or drag images into the drop zone."
        } else {
            queueHintLabel.stringValue = "Tip: Pick an output folder so optimized files keep the same base name safely."
        }
    }

    private func updateDashboard() {
        let totalBytes = selectedFiles.reduce(Int64(0)) { partial, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            return partial + size
        }

        queuedValueLabel.stringValue = "\(selectedFiles.count) file(s)"
        queuedDetailLabel.stringValue = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        targetValueLabel.stringValue = maxSizeField.stringValue.uppercased()
        targetDetailLabel.stringValue = "Fast WebP target"

        let mode = saveModePopup.titleOfSelectedItem ?? "same-name"
        let prettyMode = mode
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
        outputValueLabel.stringValue = prettyMode
        outputDetailLabel.stringValue = "best extension"

        switch maxSizeField.stringValue.lowercased() {
        case "150kb": targetPresetControl.selectedSegment = 0
        case "300kb": targetPresetControl.selectedSegment = 1
        case "500kb": targetPresetControl.selectedSegment = 2
        case "2mb": targetPresetControl.selectedSegment = 3
        default: targetPresetControl.selectedSegment = -1
        }
    }

    private func updateSaveModeUI() {
        let mode = saveModePopup.titleOfSelectedItem ?? "same-name"
        switch mode {
        case "same-name":
            outputFolderField.isEnabled = true
            chooseOutputButton.isEnabled = true
            clearOutputButton.isEnabled = true
            saveModeHintLabel.stringValue = "Fast mode keeps the base filename and can switch extension to hit the target size."
        case "overwrite":
            outputFolderField.isEnabled = false
            chooseOutputButton.isEnabled = false
            clearOutputButton.isEnabled = false
            saveModeHintLabel.stringValue = "Overwrite is unavailable in same-name output mode."
        default:
            saveModePopup.selectItem(withTitle: "same-name")
            outputFolderField.isEnabled = true
            chooseOutputButton.isEnabled = true
            clearOutputButton.isEnabled = true
            saveModeHintLabel.stringValue = "Fast mode keeps the base filename and can switch extension."
        }
    }

    private func setRunning(_ running: Bool) {
        isRunning = running
        compressButton.isEnabled = !running
        stopButton.isEnabled = running
        if running {
            progressIndicator.startAnimation(nil)
        } else {
            progressIndicator.stopAnimation(nil)
        }
    }

    private func resetCompressionStopState() {
        compressionProcessLock.lock()
        stopRequested = false
        activeCompressionProcesses.removeAll()
        compressionProcessLock.unlock()
    }

    private func isCompressionStopRequested() -> Bool {
        compressionProcessLock.lock()
        let value = stopRequested
        compressionProcessLock.unlock()
        return value
    }

    private func registerCompressionProcess(_ process: Process) {
        compressionProcessLock.lock()
        activeCompressionProcesses.append(process)
        let shouldStop = stopRequested
        compressionProcessLock.unlock()

        if shouldStop, process.isRunning {
            process.terminate()
        }
    }

    private func unregisterCompressionProcess(_ process: Process) {
        compressionProcessLock.lock()
        activeCompressionProcesses.removeAll { $0 === process }
        compressionProcessLock.unlock()
    }

    private func resetBatchProgress(total: Int = 0) {
        batchProgressIndicator.minValue = 0
        batchProgressIndicator.maxValue = Double(max(total, 1))
        batchProgressIndicator.doubleValue = 0
        batchProgressLabel.stringValue = total > 0 ? "0 complete / \(total) left" : "0 complete / 0 left"
    }

    private func updateBatchProgress(completed: Int, total: Int) {
        let safeTotal = max(total, 0)
        let safeCompleted = min(max(completed, 0), safeTotal)
        let remaining = max(safeTotal - safeCompleted, 0)
        batchProgressIndicator.maxValue = Double(max(safeTotal, 1))
        batchProgressIndicator.doubleValue = Double(safeCompleted)
        batchProgressLabel.stringValue = "\(safeCompleted) complete / \(remaining) left"
    }

    private func resetPendingBatchUI() {
        batchUILock.lock()
        pendingBatchLogLines.removeAll()
        pendingBatchCompleted = 0
        isBatchUIFlushScheduled = false
        batchUILock.unlock()
    }

    private func queueBatchUIUpdate(lines: [String], completed: Int, total: Int) {
        var shouldScheduleFlush = false

        batchUILock.lock()
        pendingBatchLogLines.append(contentsOf: lines)
        pendingBatchCompleted = max(pendingBatchCompleted, completed)
        if !isBatchUIFlushScheduled {
            isBatchUIFlushScheduled = true
            shouldScheduleFlush = true
        }
        batchUILock.unlock()

        if shouldScheduleFlush {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.flushPendingBatchUI(total: total, autoScroll: false)
            }
        }
    }

    private func flushPendingBatchUI(total: Int, autoScroll: Bool) {
        batchUILock.lock()
        let lines = pendingBatchLogLines
        let completed = pendingBatchCompleted
        pendingBatchLogLines.removeAll()
        isBatchUIFlushScheduled = false
        batchUILock.unlock()

        guard !lines.isEmpty || completed > 0 else { return }
        appendLogLines(lines, autoScroll: autoScroll)
        updateBatchProgress(completed: completed, total: total)
    }

    private func appendLog(_ line: String) {
        appendLogLines([line], autoScroll: true)
    }

    private func appendLogLines(_ lines: [String], autoScroll: Bool) {
        guard !lines.isEmpty else { return }
        let output = NSMutableAttributedString()

        for line in lines {
            let logColor: NSColor
            if line.contains("[ERROR]") {
                logColor = Palette.danger
            } else if line.contains("[BEST EFFORT]") {
                logColor = Palette.warning
            } else if line.contains("[OK]") || line.contains("[UNCHANGED]") {
                logColor = Palette.success
            } else {
                logColor = Palette.text
            }

            output.append(NSAttributedString(
                string: line + "\n",
                attributes: [
                    .foregroundColor: logColor,
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                ]
            ))
            logger.write(line)
        }

        logTextView.textStorage?.append(output)
        if autoScroll {
            logTextView.scrollToEndOfDocument(nil)
        }
    }


    func startupDiagnosticsReport() -> String? {
        guard let resourceURL = Bundle.main.resourceURL else {
            return "[DIAG] Missing bundle resource URL."
        }
        let runtimeURL = resourceURL.appendingPathComponent("runtime", isDirectory: true)
        let imageScript = runtimeURL.appendingPathComponent("compress_image.py").path
        let videoScript = runtimeURL.appendingPathComponent("compress_video.py").path
        let py3 = runtimeURL.appendingPathComponent(".venv/bin/python3").path
        let python = runtimeURL.appendingPathComponent(".venv/bin/python").path
        let checks = [
            ("runtime folder", FileManager.default.fileExists(atPath: runtimeURL.path)),
            ("compress_image.py", FileManager.default.fileExists(atPath: imageScript)),
            ("compress_video.py", FileManager.default.fileExists(atPath: videoScript)),
            ("venv python3", FileManager.default.fileExists(atPath: py3) || FileManager.default.fileExists(atPath: python)),
        ]
        let parts = checks.map { "\($0.0): \($0.1 ? "OK" : "MISSING")" }
        return "[DIAG] " + parts.joined(separator: " | ") + " | log: \(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Image Compressor.log").path)"
    }

    func setStartupStatus(_ message: String) {
        statusLabel.stringValue = message
        appendLog(message)
    }

    private func sendCompletionNotification(_ message: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = "Image Compressor"
        content.body = message
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(req, withCompletionHandler: nil)
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        selectedFiles.count
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        ModernTableRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("file-cell")
        let label: NSTextField

        if let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView,
           let existingLabel = cell.textField {
            label = existingLabel
        } else {
            let cell = NSTableCellView()
            cell.identifier = identifier
            label = makeLabel("", size: 12, weight: .medium, color: Palette.text)
            label.translatesAutoresizingMaskIntoConstraints = false
            label.lineBreakMode = .byTruncatingMiddle
            cell.textField = label
            cell.addSubview(label)

            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])

            return cell
        }

        let url = selectedFiles[row]
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let status = fileStates[queueStatusKey(url)]?.status.rawValue ?? QueueFileStatus.queued.rawValue
        label.stringValue = "[\(status)] \(url.lastPathComponent) | \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) | \(url.deletingLastPathComponent().path)"
        return label.superview
    }
}

private func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = premiumFont(size: size, weight: weight)
    label.textColor = color
    label.backgroundColor = .clear
    label.isBezeled = false
    label.drawsBackground = false
    label.lineBreakMode = .byTruncatingTail
    return label
}

private func premiumFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
    NSFont.systemFont(ofSize: size, weight: weight)
}

private func makeSymbolImage(_ symbolName: String, pointSize: CGFloat) -> NSImage? {
    let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .light)
    return NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration)
}

private func makeSymbolBadge(symbol: String, tint: NSColor) -> NSView {
    let badge = NSVisualEffectView()
    badge.translatesAutoresizingMaskIntoConstraints = false
    badge.material = .hudWindow
    badge.blendingMode = .withinWindow
    badge.state = .active
    badge.wantsLayer = true
    badge.layer?.backgroundColor = tint.withAlphaComponent(0.12).cgColor
    badge.layer?.cornerRadius = 19
    badge.layer?.cornerCurve = .continuous
    badge.layer?.borderWidth = 1
    badge.layer?.borderColor = NSColor.white.withAlphaComponent(0.20).cgColor
    badge.layer?.shadowColor = tint.withAlphaComponent(0.36).cgColor
    badge.layer?.shadowOpacity = 1
    badge.layer?.shadowOffset = .zero
    badge.layer?.shadowRadius = 10

    let icon = NSImageView()
    icon.translatesAutoresizingMaskIntoConstraints = false
    icon.image = makeSymbolImage(symbol, pointSize: 14)
    icon.contentTintColor = tint
    badge.addSubview(icon)

    NSLayoutConstraint.activate([
        badge.widthAnchor.constraint(equalToConstant: 38),
        badge.heightAnchor.constraint(equalToConstant: 38),
        icon.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
        icon.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
    ])

    return badge
}

private func makeHighlightPill(symbol: String, text: String) -> NSView {
    let pill = NSStackView()
    pill.orientation = .horizontal
    pill.alignment = .centerY
    pill.spacing = 8
    pill.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 12)
    pill.wantsLayer = true
    pill.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
    pill.layer?.cornerRadius = 999
    pill.layer?.borderWidth = 1
    pill.layer?.borderColor = NSColor.white.withAlphaComponent(0.20).cgColor
    pill.addArrangedSubview(makeSymbolBadge(symbol: symbol, tint: Palette.accentBright))
    pill.addArrangedSubview(makeLabel(text, size: 12, weight: .semibold, color: Palette.text))
    return pill
}

private func makeWrappingLabel(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: text)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = premiumFont(size: size, weight: weight)
    label.textColor = color
    label.maximumNumberOfLines = 0
    return label
}

private func makeBadgeLabel(_ text: String) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = premiumFont(size: 11, weight: .medium)
    label.textColor = Palette.champagne
    label.wantsLayer = true
    label.layer?.backgroundColor = Palette.champagne.withAlphaComponent(0.10).cgColor
    label.layer?.cornerRadius = 999
    label.layer?.borderWidth = 1
    label.layer?.borderColor = Palette.champagne.withAlphaComponent(0.25).cgColor
    label.alignment = .center
    label.cell?.usesSingleLineMode = true
    label.setContentHuggingPriority(.required, for: .horizontal)
    label.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
    label.heightAnchor.constraint(equalToConstant: 28).isActive = true
    return label
}

private func styleSecondaryButton(_ button: NSButton) {
    button.translatesAutoresizingMaskIntoConstraints = false
    button.isBordered = false
    button.bezelStyle = .regularSquare
    button.font = premiumFont(size: 13, weight: .semibold)
    button.wantsLayer = true
    button.layer?.backgroundColor = Palette.secondaryButton.cgColor
    button.layer?.cornerRadius = 10
    button.layer?.cornerCurve = .continuous
    button.layer?.borderWidth = 1.15
    button.layer?.borderColor = NSColor.white.withAlphaComponent(0.26).cgColor
    button.layer?.shadowColor = NSColor.black.withAlphaComponent(0.22).cgColor
    button.layer?.shadowOpacity = 1
    button.layer?.shadowOffset = CGSize(width: 0, height: -8)
    button.layer?.shadowRadius = 14
    button.contentTintColor = Palette.secondaryButtonText
    button.imagePosition = .imageLeading
    button.imageHugsTitle = true
    button.heightAnchor.constraint(equalToConstant: 46).isActive = true
}

private func stylePrimaryButton(_ button: NSButton) {
    button.translatesAutoresizingMaskIntoConstraints = false
    button.isBordered = false
    button.bezelStyle = .regularSquare
    button.font = premiumFont(size: 13, weight: .semibold)
    button.wantsLayer = true
    button.layer?.backgroundColor = Palette.primaryButton.cgColor
    button.layer?.cornerRadius = 10
    button.layer?.cornerCurve = .continuous
    button.layer?.borderWidth = 1.2
    button.layer?.borderColor = NSColor.white.withAlphaComponent(0.40).cgColor
    button.layer?.shadowColor = Palette.primaryButtonPressed.withAlphaComponent(0.58).cgColor
    button.layer?.shadowOpacity = 1
    button.layer?.shadowOffset = .zero
    button.layer?.shadowRadius = 24
    button.contentTintColor = NSColor.white
    button.imagePosition = .imageLeading
    button.imageHugsTitle = true
    button.heightAnchor.constraint(equalToConstant: 52).isActive = true
}

private func styleDangerButton(_ button: NSButton) {
    button.translatesAutoresizingMaskIntoConstraints = false
    button.isBordered = false
    button.bezelStyle = .regularSquare
    button.font = premiumFont(size: 13, weight: .semibold)
    button.wantsLayer = true
    button.layer?.backgroundColor = Palette.dangerButton.cgColor
    button.layer?.cornerRadius = 10
    button.layer?.cornerCurve = .continuous
    button.layer?.borderWidth = 1.1
    button.layer?.borderColor = NSColor.white.withAlphaComponent(0.28).cgColor
    button.layer?.shadowColor = Palette.dangerButton.withAlphaComponent(0.52).cgColor
    button.layer?.shadowOpacity = 1
    button.layer?.shadowOffset = CGSize(width: 0, height: -6)
    button.layer?.shadowRadius = 14
    button.contentTintColor = NSColor.white
    button.imagePosition = .imageLeading
    button.imageHugsTitle = true
    button.heightAnchor.constraint(equalToConstant: 46).isActive = true
}

private func stylePopup(_ popup: NSPopUpButton) {
    popup.translatesAutoresizingMaskIntoConstraints = false
    popup.font = premiumFont(size: 13, weight: .semibold)
    popup.contentTintColor = Palette.text
    popup.wantsLayer = true
    popup.layer?.backgroundColor = Palette.pill.cgColor
    popup.layer?.cornerRadius = 10
    popup.layer?.cornerCurve = .continuous
    popup.layer?.borderWidth = 1
    popup.layer?.borderColor = Palette.border.cgColor
    popup.heightAnchor.constraint(equalToConstant: 46).isActive = true
}

private func configureButtonImage(_ button: NSButton, symbolName: String) {
    button.image = makeSymbolImage(symbolName, pointSize: 13)
}

private final class ModernTableRowView: NSTableRowView {
    override func drawBackground(in dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()
    }

    override func drawSelection(in dirtyRect: NSRect) {
        let insetRect = bounds.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(roundedRect: insetRect, xRadius: 12, yRadius: 12)
        Palette.accentSoft.withAlphaComponent(0.45).setFill()
        path.fill()
    }
}
